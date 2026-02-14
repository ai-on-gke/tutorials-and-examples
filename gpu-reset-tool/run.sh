#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Check for required environment variables
if [ -z "${NODE_NAME}" ]; then
  echo "Error: NODE_NAME environment variable is not set."
  echo "Usage: export NODE_NAME=<your-node-name>"
  exit 1
fi

# Set default for RESET_THRESHOLD_DAYS if not provided
export RESET_THRESHOLD_DAYS=${RESET_THRESHOLD_DAYS:-60}

# Check if the node exists
echo "Verifying node ${NODE_NAME} exists..."
if ! kubectl get node "${NODE_NAME}" > /dev/null 2>&1; then
  echo "Error: Node ${NODE_NAME} not found in the cluster."
  exit 1
fi
echo "Node ${NODE_NAME} found."


SCRIPT_DIR=$(dirname "$0")
YAML_FILE="${SCRIPT_DIR}/gpu-reset-job.yaml"

if [ ! -f "${YAML_FILE}" ]; then
  echo "Error: YAML file not found at ${YAML_FILE}"
  exit 1
fi

echo "Ensuring ServiceAccount gpu-reset-sa exists..."
kubectl apply -f "${SCRIPT_DIR}/gpu-reset-sa.yaml"

echo "Applying GPU reset pod to node: ${NODE_NAME}"
echo "Using RESET_THRESHOLD_DAYS: ${RESET_THRESHOLD_DAYS}"

# Substitute environment variables and apply the manifest
# Substitute placeholders using sed and apply the manifest
JOB_NAME=$(cat "${YAML_FILE}" | \
  sed "s/##NODE_NAME##/${NODE_NAME}/g" | \
  sed "s/##RESET_THRESHOLD_DAYS##/${RESET_THRESHOLD_DAYS}/g" | \
  kubectl create -f - -o json | jq -r '.metadata.name')

if [ -z "${JOB_NAME}" ]; then
  echo "Error: Failed to create job."
  exit 1
fi

echo "Job ${JOB_NAME} created."

# Wait for the pod to be created and running
echo "Waiting for pod for job ${JOB_NAME}..."
POD_NAME=""
POD_PHASE="Pending"
for i in {1..60}; do
  POD_NAME=$(kubectl get pods -n default -l job-name=${JOB_NAME} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "${POD_NAME}" ]; then
    POD_PHASE=$(kubectl get pod ${POD_NAME} -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    if [ "${POD_PHASE}" == "Running" ] || [ "${POD_PHASE}" == "Succeeded" ] || [ "${POD_PHASE}" == "Failed" ]; then
      break
    fi
  fi
  echo "  Job: ${JOB_NAME}, Pod: ${POD_NAME:-<none>}, Phase: ${POD_PHASE} (Attempt $i/60)"
  sleep 2
done

if [ "${POD_PHASE}" != "Running" ] && [ "${POD_PHASE}" != "Succeeded" ] && [ "${POD_PHASE}" != "Failed" ]; then
  echo "Error: Pod for job ${JOB_NAME} did not become ready within 120 seconds."
  [ -n "${POD_NAME}" ] && kubectl describe pod ${POD_NAME} -n default
  exit 1
fi
echo "Pod ${POD_NAME} is ${POD_PHASE}"

# Stream logs in the background
echo "--- Streaming logs from Pod ${POD_NAME} --- "
kubectl logs -f ${POD_NAME} -n default &
LOGS_PID=$!

# Kill the logs process on exit
trap 'kill $LOGS_PID 2>/dev/null' EXIT

echo "Waiting for job ${JOB_NAME} to complete... (Timeout: 15m)"
JOB_SUCCESS=0
JOB_FAILED=0
for i in {1..180}; do # Check every 5 seconds for 15 minutes
  if kubectl get job ${JOB_NAME} -n default -o jsonpath='{.status.succeeded}' | grep -q 1; then
    echo "Job ${JOB_NAME} completed successfully."
    JOB_SUCCESS=1
    break
  fi
  if kubectl get job ${JOB_NAME} -n default -o jsonpath='{.status.failed}' | grep -q 1; then
    echo "Error: Job ${JOB_NAME} failed."
    JOB_FAILED=1
    break
  fi
  sleep 5
done

if [ "${JOB_SUCCESS}" -eq 0 ] && [ "${JOB_FAILED}" -eq 0 ]; then
  echo "Error: Job ${JOB_NAME} timed out."
fi

# Stop streaming logs
echo "Stopping log stream (PID: $LOGS_PID)..."
kill $LOGS_PID 2>/dev/null || true
sleep 0.1
kill -9 $LOGS_PID 2>/dev/null || true

echo "--- Final log snippet from Pod ${POD_NAME} --- "
kubectl logs ${POD_NAME} -n default --tail=100 || echo "Failed to fetch final logs."
echo "--- End Logs --- "

trap - EXIT
exit ${JOB_FAILED}
