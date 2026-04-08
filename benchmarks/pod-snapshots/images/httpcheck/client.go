// Copyright 2024 The gVisor Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// A simple `curl`-like HTTP client that prints metrics after the request.
// All of its output is structured to be unambiguous even if stdout/stderr
// is combined, as is the case for Kubernetes logs.
// Useful for communicating with ollama.
//
// Also exposes a /check endpoint on --serve-addr (default :8090) that
// performs the configured request and returns all results as JSON.
package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"time"
)

// LINT.IfChange

// Flags.
var (
	url            = flag.String("url", "", "HTTP request URL.")
	method         = flag.String("method", "GET", "HTTP request method (GET or POST).")
	postDataBase64 = flag.String("post_base64", "", "HTTP request POST data in base64 format; ignored for GET requests.")
	timeout        = flag.Duration("timeout", 0, "HTTP request timeout; 0 for no timeout.")
	serveAddr      = flag.String("serve-addr", ":8090", "Address to expose the /check JSON endpoint on. Set to empty string to disable.")
)

// bufSize is the size of buffers used for HTTP requests and responses.
const bufSize = 1024 * 1024 // 1MiB

// fatalf crashes the program with a given error message.
func fatalf(format string, values ...any) {
	fmt.Fprintf(os.Stderr, "FATAL: "+format+"\n", values...)
	os.Exit(1)
}

// timePtr returns a pointer to t, or nil if t is the zero time.
// Used to omit unset timestamps from JSON and headers.
func timePtr(t time.Time) *time.Time {
	if t.IsZero() {
		return nil
	}
	return &t
}

// float64Ptr returns a pointer to f, or nil if either of the two timestamps
// used to derive it was zero (meaning the metric was never reached).
func float64Ptr(from, to time.Time) *float64 {
	if from.IsZero() || to.IsZero() {
		return nil
	}
	v := float64(to.Sub(from).Milliseconds())
	return &v
}

// Metrics contains the request metrics to export to JSON.
// All fields are pointers so that unset (zero) timestamps are omitted from
// JSON output rather than serialised as "0001-01-01T00:00:00Z".
// This is parsed by the ollama library at `test/gpu/ollama/ollama.go`.
type Metrics struct {
	// ProgramStarted is the time when the program started.
	ProgramStarted *time.Time `json:"program_started,omitempty"`
	// RequestSent is the time when the HTTP request was sent.
	RequestSent *time.Time `json:"request_sent,omitempty"`
	// ResponseReceived is the time when the HTTP response headers were received.
	ResponseReceived *time.Time `json:"response_received,omitempty"`
	// FirstByteRead is the time when the first HTTP response body byte was read.
	FirstByteRead *time.Time `json:"first_byte_read,omitempty"`
	// LastByteRead is the time when the last HTTP response body byte was read.
	LastByteRead *time.Time `json:"last_byte_read,omitempty"`
}

// CheckResponse is the full JSON response returned by the /check endpoint.
type CheckResponse struct {
	// Success indicates whether the upstream request completed without error.
	Success bool `json:"success"`
	// Error holds the error message if Success is false.
	Error string `json:"error,omitempty"`
	// StatusCode is the HTTP status code returned by the upstream server.
	StatusCode int `json:"status_code,omitempty"`
	// RequestHeaders are the headers that were sent with the upstream request.
	RequestHeaders map[string][]string `json:"request_headers,omitempty"`
	// ResponseHeaders are the headers returned by the upstream server.
	ResponseHeaders map[string][]string `json:"response_headers,omitempty"`
	// Body is the full response body as a string.
	Body string `json:"body,omitempty"`
	// Metrics holds the timing breakdown for the request.
	Metrics Metrics `json:"metrics"`
	// DerivedMs holds human-friendly derived durations in milliseconds.
	DerivedMs DerivedMetrics `json:"derived_ms"`
}

// DerivedMetrics holds computed durations derived from the raw Metrics timestamps.
// All fields are pointers so that metrics whose source timestamps were never
// reached are omitted from JSON output rather than emitted as 0.
type DerivedMetrics struct {
	// TimeToFirstByte is the duration from RequestSent to FirstByteRead, in ms.
	TimeToFirstByte *float64 `json:"time_to_first_byte_ms,omitempty"`
	// TotalTransfer is the duration from FirstByteRead to LastByteRead, in ms.
	TotalTransfer *float64 `json:"total_transfer_ms,omitempty"`
	// TotalRequest is the duration from RequestSent to LastByteRead, in ms.
	TotalRequest *float64 `json:"total_request_ms,omitempty"`
}

// writeMetricHeaders writes each available timing metric as a response header.
// Metrics whose timestamps were not reached (nil) are silently skipped.
// Header names follow the X-Metric-* convention for easy filtering in proxies.
func writeMetricHeaders(w http.ResponseWriter, m Metrics, d DerivedMetrics) {
	setTimeHeader := func(name string, t *time.Time) {
		if t != nil {
			w.Header().Set(name, t.UTC().Format(time.RFC3339Nano))
		}
	}
	setFloat64Header := func(name string, f *float64) {
		if f != nil {
			w.Header().Set(name, fmt.Sprintf("%.3f", *f))
		}
	}

	setTimeHeader("X-Metric-Program-Started", m.ProgramStarted)
	setTimeHeader("X-Metric-Request-Sent", m.RequestSent)
	setTimeHeader("X-Metric-Response-Received", m.ResponseReceived)
	setTimeHeader("X-Metric-First-Byte-Read", m.FirstByteRead)
	setTimeHeader("X-Metric-Last-Byte-Read", m.LastByteRead)

	setFloat64Header("X-Metric-Time-To-First-Byte-Ms", d.TimeToFirstByte)
	setFloat64Header("X-Metric-Total-Transfer-Ms", d.TotalTransfer)
	setFloat64Header("X-Metric-Total-Request-Ms", d.TotalRequest)
}

// rawMetrics is the internal mutable form used during doRequest.
// Converted to the pointer-based Metrics struct at the end.
type rawMetrics struct {
	programStarted   time.Time
	requestSent      time.Time
	responseReceived time.Time
	firstByteRead    time.Time
	lastByteRead     time.Time
}

// toMetrics converts rawMetrics into the exported Metrics struct,
// omitting any timestamp that was never set (zero value).
func (r rawMetrics) toMetrics() Metrics {
	return Metrics{
		ProgramStarted:   timePtr(r.programStarted),
		RequestSent:      timePtr(r.requestSent),
		ResponseReceived: timePtr(r.responseReceived),
		FirstByteRead:    timePtr(r.firstByteRead),
		LastByteRead:     timePtr(r.lastByteRead),
	}
}

// toDerivedMetrics builds DerivedMetrics from rawMetrics, omitting any
// derived value whose source timestamps were not both reached.
func (r rawMetrics) toDerivedMetrics() DerivedMetrics {
	return DerivedMetrics{
		TimeToFirstByte: float64Ptr(r.requestSent, r.firstByteRead),
		TotalTransfer:   float64Ptr(r.firstByteRead, r.lastByteRead),
		TotalRequest:    float64Ptr(r.requestSent, r.lastByteRead),
	}
}

// doRequest performs the configured HTTP request and returns a CheckResponse.
func doRequest(programStarted time.Time) CheckResponse {
	var result CheckResponse
	var raw rawMetrics
	raw.programStarted = programStarted

	client := http.Client{
		Transport: &http.Transport{
			MaxIdleConns:    1,
			IdleConnTimeout: *timeout,
			ReadBufferSize:  bufSize,
			WriteBufferSize: bufSize,
		},
		Timeout: *timeout,
	}

	var request *http.Request
	var err error
	switch *method {
	case "GET":
		request, err = http.NewRequest("GET", *url, nil)
	case "POST":
		postData, postDataErr := base64.StdEncoding.DecodeString(*postDataBase64)
		if postDataErr != nil {
			result.Error = fmt.Sprintf("cannot decode POST data: %v", postDataErr)
			result.Metrics = raw.toMetrics()
			result.DerivedMs = raw.toDerivedMetrics()
			return result
		}
		request, err = http.NewRequest("POST", *url, bytes.NewBuffer(postData))
	default:
		result.Error = fmt.Sprintf("unknown method %q", *method)
		result.Metrics = raw.toMetrics()
		result.DerivedMs = raw.toDerivedMetrics()
		return result
	}
	if err != nil {
		result.Error = fmt.Sprintf("cannot create request: %v", err)
		result.Metrics = raw.toMetrics()
		result.DerivedMs = raw.toDerivedMetrics()
		return result
	}

	result.RequestHeaders = map[string][]string(request.Header)

	raw.requestSent = time.Now()
	resp, err := client.Do(request)
	raw.responseReceived = time.Now()
	if err != nil {
		result.Error = fmt.Sprintf("cannot make request: %v", err)
		result.Metrics = raw.toMetrics()
		result.DerivedMs = raw.toDerivedMetrics()
		return result
	}
	defer resp.Body.Close()

	result.StatusCode = resp.StatusCode
	result.ResponseHeaders = map[string][]string(resp.Header)

	var bodyBuf bytes.Buffer
	readBuf := make([]byte, bufSize)
	gotFirstByte := false
	for {
		n, readErr := resp.Body.Read(readBuf)
		if n > 0 {
			if !gotFirstByte {
				raw.firstByteRead = time.Now()
				gotFirstByte = true
			}
			bodyBuf.Write(readBuf[:n])
		}
		if readErr == io.EOF {
			raw.lastByteRead = time.Now()
			break
		}
		if readErr != nil {
			result.Error = fmt.Sprintf("cannot read response body: %v", readErr)
			result.Metrics = raw.toMetrics()
			result.DerivedMs = raw.toDerivedMetrics()
			return result
		}
	}

	result.Body = bodyBuf.String()
	result.Success = true
	result.Metrics = raw.toMetrics()
	result.DerivedMs = raw.toDerivedMetrics()
	return result
}

// runCLI performs the original CLI behaviour: prints headers/body/stats to
// stdout/stderr in the prefixed line format expected by the test framework.
func runCLI(programStarted time.Time) {
	result := doRequest(programStarted)

	if !result.Success {
		fatalf("%s", result.Error)
	}

	orderedReqHeaders := make([]string, 0, len(result.RequestHeaders))
	for k := range result.RequestHeaders {
		orderedReqHeaders = append(orderedReqHeaders, k)
	}
	sort.Strings(orderedReqHeaders)
	for _, k := range orderedReqHeaders {
		for _, v := range result.RequestHeaders[k] {
			fmt.Fprintf(os.Stderr, "REQHEADER: %s: %s\n", k, v)
		}
	}

	fmt.Printf("BODY: %q\n", result.Body)

	orderedRespHeaders := make([]string, 0, len(result.ResponseHeaders))
	for k := range result.ResponseHeaders {
		orderedRespHeaders = append(orderedRespHeaders, k)
	}
	sort.Strings(orderedRespHeaders)
	for _, k := range orderedRespHeaders {
		for _, v := range result.ResponseHeaders[k] {
			fmt.Fprintf(os.Stderr, "RESPHEADER: %s: %s\n", k, v)
		}
	}

	metricsBytes, err := json.Marshal(&result.Metrics)
	if err != nil {
		fatalf("cannot marshal metrics: %v", err)
	}
	fmt.Fprintf(os.Stderr, "STATS: %s\n", string(metricsBytes))
}

func main() {
	programStarted := time.Now()
	flag.Parse()

	if *url == "" {
		fatalf("--url is required")
	}

	// If serve-addr is set, run as an HTTP server exposing /check.
	if *serveAddr != "" {
		fmt.Fprintf(os.Stderr, "Serving /check on %s\n", *serveAddr)
		http.HandleFunc("/check", func(w http.ResponseWriter, r *http.Request) {
			result := doRequest(programStarted)

			// Write metric headers before the status code; headers whose
			// source timestamps were not reached are silently skipped.
			writeMetricHeaders(w, result.Metrics, result.DerivedMs)

			w.Header().Set("Content-Type", "application/json")
			if !result.Success {
				w.WriteHeader(http.StatusBadGateway)
			}
			if err := json.NewEncoder(w).Encode(result); err != nil {
				fmt.Fprintf(os.Stderr, "failed to write /check response: %v\n", err)
			}
		})
		if err := http.ListenAndServe(*serveAddr, nil); err != nil {
			fatalf("server error: %v", err)
		}
		return
	}

	// Otherwise fall back to the original CLI behaviour.
	runCLI(programStarted)
}

// LINT.ThenChange(../../sglang/client/client.go)