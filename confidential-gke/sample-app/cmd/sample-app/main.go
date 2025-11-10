// Package main retreives encrypted data on a GCS bucket and decrypts it using an attestation token and Cloud KMS.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"

	storage "cloud.google.com/go/storage"
	"github.com/tink-crypto/tink-go-gcpkms/v2/integration/gcpkms"
	"github.com/tink-crypto/tink-go/v2/aead"
	option "google.golang.org/api/option"
)

var (
	kekURI        = flag.String("kek_uri", "", "The Cloud KMS URI of the key encryption key.")
	gcsBlobPath   = flag.String("gcs_blob_path", "", "Path to the GCS blob.")
	projectNumber = flag.String("project_number", "", "Project number where workload identity pool is located.")
	wipName       = flag.String("wip_name", "", "Workload Identity Pool name.")
	wipProvider   = flag.String("wip_provider", "", "Workload Identity Pool provider for attestation.")
)

const (
	socketPath           = "/run/launcher-agent/teeserver.sock"
	tokenEndpoint        = "http://localhost/v1/gke/token"
	attestationTokenPath = "/data/attestation_verifier_claims_token"
)

type credentialSource struct {
	FilePath string `json:"file"`
}

type credentialConfig struct {
	UniverseDomain   string           `json:"universe_domain"`
	CredentialType   string           `json:"type"`
	Audience         string           `json:"audience"`
	SubjectTokenType string           `json:"subject_token_type"`
	TokenURL         string           `json:"token_url"`
	CredentialSource credentialSource `json:"credential_source"`
}

func main() {
	flag.Parse()

	// register sample function to handle all requests
	mux := http.NewServeMux()
	mux.HandleFunc("/", sample)

	// use PORT environment variable, or default to 8080
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// start the web server on port and accept requests
	log.Printf("Server listening on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func sample(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	log.Printf("Serving request: %s", r.URL.Path)

	if err := validateFlags(); err != nil {
		fmt.Fprintf(w, "error validating flags: %v", err)
		return
	}

	audience := fmt.Sprintf("//iam.googleapis.com/projects/%s/locations/global/workloadIdentityPools/%s/providers/%s", *projectNumber, *wipName, *wipProvider)
	credConfig := credentialConfig{
		UniverseDomain:   "googleapis.com",
		CredentialType:   "external_account",
		Audience:         audience,
		SubjectTokenType: "urn:ietf:params:oauth:token-type:jwt",
		TokenURL:         "https://sts.googleapis.com/v1/token",
		CredentialSource: credentialSource{
			FilePath: attestationTokenPath,
		},
	}
	credConfigJSON, err := json.Marshal(credConfig)
	if err != nil {
		fmt.Fprintf(w, "error marshaling credential config: %v\n", err)
		return
	}
	fmt.Fprintf(w, "Using Credential Config:\n%s\n", string(credConfigJSON))

	host, _ := os.Hostname()
	fmt.Fprintf(w, "Hostname: %s\n", host)

	jwt, err := getJwt()
	if err != nil {
		fmt.Fprintf(w, "Error getting JWT: %s\n", err)
	} else {
		fmt.Fprintf(w, "JWT: %s\n", jwt)
	}

	data := []byte(jwt)

	// Write the data to the file with read/write permissions for the owner
	err = os.WriteFile(attestationTokenPath, data, 0644)
	if err != nil {
		fmt.Printf("Error writing to file: %v\n", err)
		return
	}

	file, err := getFileFromGCS(ctx, credConfigJSON)
	if err != nil {
		fmt.Fprintf(w, "Error getting file from GCS: %s\n", err)
		return
	} else {
		fmt.Fprintf(w, "Succesfully downloaded encrypted file from GCS\n")
	}

	decrypted, err := gcpKmsKeyEnvelopeAeadDecrypt(ctx, credConfigJSON, []byte(file), *kekURI)
	if err != nil {
		fmt.Fprintf(w, "Error decrypting file: %s\n", err)
	} else {
		fmt.Fprintf(w, "Decrypted file:\n%s\n", string(decrypted))
	}

}

func getJwt() (string, error) {
	httpClient := http.Client{
		Transport: &http.Transport{
			// Set the DialContext field to a function that creates
			// a new network connection to a Unix domain socket
			DialContext: func(_ context.Context, _, _ string) (net.Conn, error) {
				return net.Dial("unix", socketPath)
			},
		},
	}

	resp, err := httpClient.Get(tokenEndpoint)
	if err != nil {
		return "", err
	}

	log.Printf("Response from launcher: %v\n", resp)
	text, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read resp.Body: %w", err)
	}
	log.Printf("Token from the attestation service: %s\n", text)

	return string(text), nil
}

func getFileFromGCS(ctx context.Context, credConfig []byte) (string, error) {

	client, err := storage.NewClient(ctx, option.WithCredentialsJSON(credConfig))
	if err != nil {
		return "", fmt.Errorf("failed to create storage client: %w", err)
	}
	defer client.Close()

	bucket, object, err := getBucketAndObject(*gcsBlobPath)
	if err != nil {
		return "", err
	}

	reader, err := client.Bucket(bucket).Object(object).NewReader(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to create reader: %w", err)
	}
	defer reader.Close()

	bytes, err := io.ReadAll(reader)
	if err != nil {
		return "", fmt.Errorf("failed to read all bytes: %w", err)
	}

	return string(bytes), nil
}

func gcpKmsKeyEnvelopeAeadDecrypt(ctx context.Context, credConfig, ciphertext []byte, kekURI string) ([]byte, error) {

	client, err := gcpkms.NewClientWithOptions(ctx, kekURI, option.WithCredentialsJSON(credConfig))
	if err != nil {
		return nil, fmt.Errorf("failed to create handle: %w", err)
	}

	kekAEAD, err := client.GetAEAD(kekURI)
	if err != nil {
		return nil, fmt.Errorf("failed to create AEAD: %w", err)
	}

	associatedData := []byte(*gcsBlobPath)
	primitive := aead.NewKMSEnvelopeAEAD2(aead.AES256GCMKeyTemplate(), kekAEAD)
	decrypted, err := primitive.Decrypt(ciphertext, associatedData)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt: %w", err)
	}
	return decrypted, nil
}

func getBucketAndObject(blobPath string) (string, string, error) {
	const gcsPrefix = "gs://"
	if !strings.HasPrefix(blobPath, gcsPrefix) {
		return "", "", fmt.Errorf("GCS Path must start with prefix %s: %s", gcsPrefix, blobPath)
	}
	path := blobPath[len(gcsPrefix):]
	parts := strings.Split(path, "/")
	if len(parts) < 2 {
		return "", "", fmt.Errorf("GCS blob paths must be in format gs://bucket-name/object-name, got %s", blobPath)
	}
	return parts[0], parts[1], nil
}

func validateFlags() error {
	if *kekURI == "" {
		return fmt.Errorf("kek_uri flag can not be empty")
	}
	if *gcsBlobPath == "" {
		return fmt.Errorf("gcs_blob_path flag can not be empty")
	}
	if *projectNumber == "" {
		return fmt.Errorf("project_number flag can not be empty")
	}
	if *wipName == "" {
		return fmt.Errorf("wip_name flag can not be empty")
	}
	if *wipProvider == "" {
		return fmt.Errorf("wip_provider flag can not be empty")
	}
	return nil
}
