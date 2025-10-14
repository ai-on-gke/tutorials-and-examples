#!/bin/bash
# Copyright 2025 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ---
# AI Inference Load Generator
#
# This script sends a continuous stream of POST requests to a local LLM
# endpoint to generate load for testing autoscaling.
#
# Usage: ./request-looper.sh [PORT] [MODEL_NAME] ["MESSAGE CONTENT"]
#
# Examples:
#   ./request-looper.sh
#   ./request-looper.sh 8082
#   ./request-looper.sh 8082 "google/gemma-2b" "What is the capital of France?"
# ---

# --- Configuration ---
PORT=${1:-"8081"}
MODEL=${2:-"google/gemma-3-1b-it"}
CONTENT=${3:-"Explain Quantum Computing in simple terms."}

URL="http://localhost:${PORT}/v1/chat/completions"
JSON_PAYLOAD=$(printf '{
  "model": "%s",
  "messages": [{"role": "user", "content": "%s"}]
}' "$MODEL" "$CONTENT")

# --- Graceful Shutdown Logic ---
pids=()
request_count=0
start_time=$(date +%s)

cleanup() {
    echo -e "\n\nCaught signal. Shutting down gracefully..."

    # --- Summary ---
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    echo "----------------------------------------"
    echo "Test Summary"
    echo "----------------------------------------"
    echo "Total Requests Sent: ${request_count}"
    echo "Total Duration: ${duration}s"
    echo "----------------------------------------"

    echo "Terminating ${#pids[@]} background curl processes."
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null;
        then
            kill -s TERM "$pid"
        fi
    done
    echo "Cleanup complete. Exiting."
    exit 0
}

trap cleanup SIGINT SIGTERM

# --- Script Logic ---
echo "Starting request loop..."
echo "  URL: $URL"
echo "  Model: $MODEL"
echo "Press Ctrl+C to stop."
echo "----------------------------------------"

while true
do
  ((request_count++))
  echo -ne "Sending request #${request_count}..."

  (
    output=$(curl -s -w "\n%{http_code}" -X POST "$URL" \
      -H "Content-Type: application/json" \
      -d "$JSON_PAYLOAD")

    http_code="${output##*$''}"

    if [[ "$http_code" -lt 200 || "$http_code" -gt 299 ]]; then
      response_body="${output%$''}"
      echo -e "\n---" >&2
      echo "ERROR: Request #${request_count} failed at $(date) with Status: ${http_code}" >&2
      echo "Response Body:" >&2
      echo "${response_body}" >&2
      echo -e "---\n" >&2
    else
      echo " Success (HTTP ${http_code})"
    fi
  ) &

  pids+=($!)

  sleep 1
done