#!/bin/bash

# --- Configurations ---
KUBECONFIG_PATH=$1
CLUSTER_NAME=$2
REPORT_DIR="./metric-gathering/test-results-gke"
CL2_DIR="${REPORT_DIR}/cl2"

# Ensure directories exist
mkdir -p "$REPORT_DIR"
mkdir -p "$CL2_DIR"

# --- Functions ---

CURRENT_NS=$(kubectl get ns -o json | jq -r '.items[] | select(.metadata.name | startswith("test-")) | .metadata.name' | head -n 1)

check_node_count() {
    kubectl get nodes -o json | jq '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True")) | .metadata.name' | wc -l >> "$REPORT_DIR/node_count.txt"
}

collect_all_pod_names() {
    if [ -z "$CURRENT_NS" ]; then
        CURRENT_NS=$(kubectl get ns -o json | jq -r '.items[] | select(.metadata.name | startswith("test-")) | .metadata.name' | head -n 1)
        [ -z "$CURRENT_NS" ] && return
    fi

    kubectl -n $CURRENT_NS get pods -o json | jq -c '.items[] | {pod_name: .metadata.name, creationTimestamp: .metadata.creationTimestamp}' >> "$REPORT_DIR/all_pod_names.json"
}

delete_sandboxes_and_log() {
    if [ -z "$CURRENT_NS" ]; then
        CURRENT_NS=$(kubectl get ns -o json | jq -r '.items[] | select(.metadata.name | startswith("test-")) | .metadata.name' | head -n 1)
        [ -z "$CURRENT_NS" ] && return
    fi

    if [ -z "$CURRENT_NS" ]; then
        return # No test namespace exists yet
    fi

    # 1. Fetch completed pods (keeping the full JSON object)
    COMPLETED_PODS_JSON=$(kubectl get pods -n "$CURRENT_NS" -o json | jq -c '.items[] | select(.status.conditions[]? | (.reason == "PodCompleted" and .type == "Initialized"))')

    if [ -z "$COMPLETED_PODS_JSON" ]; then
        return
    fi

    # 2. Extract Sandbox Names into a shell array (works in both Bash and Zsh)
    # The parentheses () convert the multiline output into an array of separate items
    COMPLETED_SANDBOX_NAMES=($(echo "$COMPLETED_PODS_JSON" | jq -r '.metadata.ownerReferences[0].name' | sort -u))

    # Guard rail: If the array is empty, exit early
    if [ ${#COMPLETED_SANDBOX_NAMES[@]} -eq 0 ]; then
        return
    fi

    # 3. Get Sandbox Timestamps using the array syntax
    # "${COMPLETED_SANDBOX_NAMES[@]}" safely expands into separate arguments for kubectl
    SANDBOX_MAP=$(kubectl get sandbox -n "$CURRENT_NS" "${COMPLETED_SANDBOX_NAMES[@]}" -o json | \
                jq -c 'reduce .items[] as $i ({}; . + {($i.metadata.name): $i.metadata.creationTimestamp})')

    # 4. Combine everything into a single JSON array
    # We pass the SANDBOX_MAP into jq as a variable to join it with the Pod data
    echo "$COMPLETED_PODS_JSON" | jq -c --argjson map "$SANDBOX_MAP" '
        {
            pod_name: .metadata.name,
            sandbox_name: .metadata.ownerReferences[0].name,
            creation_timestamp: $map[.metadata.ownerReferences[0].name]
        }' >> "$REPORT_DIR/completed_records.json"

    # 5. Save just the pod names for your log collection function later
    echo "$COMPLETED_PODS_JSON" | jq -r '.metadata.name' >> "$REPORT_DIR/pod_names.txt"

    # NOTE: If you actually want to delete the sandboxes in this function,
    # you can uncomment the line below:
    # kubectl delete sandbox -n "$CURRENT_NS" $COMPLETED_SANDBOX_NAMES
}

handle_unschedulable_pods() {
    # 1. Ensure Namespace exists
    if [ -z "$CURRENT_NS" ]; then
        CURRENT_NS=$(kubectl get ns -o json | jq -r '.items[] | select(.metadata.name | startswith("test-")) | .metadata.name' | head -n 1)
        [ -z "$CURRENT_NS" ] && return
    fi

    # 2. Fetch Pending/Unschedulable pods
    # We look for PodScheduled condition = False
    UNSCHEDULABLE_PODS_JSON=$(kubectl get pods -n "$CURRENT_NS" -o json | jq -c '.items[] |
        select(.status.phase == "Pending" and (.status.conditions[]? | select(.type == "PodScheduled" and .status == "False")))')

    if [ -z "$UNSCHEDULABLE_PODS_JSON" ] || [ "$UNSCHEDULABLE_PODS_JSON" == "null" ]; then
        return
    fi

    # 3. Extract metadata for logging
    # We want the Pod Name, Claim Name, and the Message (why it's not scheduling)
    echo "$UNSCHEDULABLE_PODS_JSON" | jq -c '
        {
            pod_name: .metadata.name,
            claim_name: (.metadata.ownerReferences[0].name // "none"),
            status: .status.phase,
            reason: (.status.conditions[]? | select(.type == "PodScheduled") | .reason),
            message: (.status.conditions[]? | select(.type == "PodScheduled") | .message)
        }' >> "$REPORT_DIR/unschedulable_records.json"

    # 4. Optional: Log to a summary for quick reading
    echo "[$(date +%H:%M:%S)] Found unschedulable pods. Check unschedulable_records.json for details."
}

collect_pod_logs(){
    echo "[$(date +%H:%M:%S)] Starting chunked log collection for namespace: $CURRENT_NS"

    POD_NAMES_FILE="$REPORT_DIR/pod_names.txt"
    TEMP_FILE="$REPORT_DIR/temp_logs.json"
    OUTPUT_FILE="$REPORT_DIR/all_completed_logs.json"

    # Check if we actually have pods to look for
    if [ ! -s "$POD_NAMES_FILE" ]; then
        echo "No pods recorded. Skipping."
        return
    fi

    # Process in chunks of 40
    cat "$POD_NAMES_FILE" | sort -u | xargs -L 40 | while read -r chunk; do

        # Format the OR filter for pod names
        CHUNK_FILTER=$(echo "$chunk" | sed 's/ /" OR resource.labels.pod_name="/g' | sed 's/.*/resource.labels.pod_name="&"/')

        echo "Fetching logs for a chunk of pods..."

        # UPDATED: Added resource.labels.namespace_name to the gcloud query
        gcloud logging read "resource.labels.cluster_name=\"$CLUSTER_NAME\" \
            AND resource.labels.namespace_name=\"$CURRENT_NS\" \
            AND resource.type=\"k8s_container\" \
            AND ($CHUNK_FILTER)" \
            --format="json" >> "$TEMP_FILE"
    done

    # Merge temporary arrays into one final JSON file
    if [ -f "$TEMP_FILE" ]; then
        jq -s 'add' "$TEMP_FILE" > "$OUTPUT_FILE"
        rm "$TEMP_FILE"
        echo "Successfully saved merged logs to $OUTPUT_FILE"
    fi
}

# --- Main Execution ---

echo "Starting ClusterLoader2 at $(date)"

# 1. Start ClusterLoader in the background
./perf-tests/clusterloader2/clusterloader2 \
  --testconfig="./gke-templates/config.yaml" \
  --provider=gke \
  --kubeconfig="$KUBECONFIG_PATH" \
  --v=2 \
  --report-dir="$CL2_DIR" &

# Capture the Process ID (PID) of ClusterLoader
CL2_PID=$!

# 2. Periodic loop
echo "Monitoring pods every 10 seconds while PID $CL2_PID is running..."

while ps -p $CL2_PID > /dev/null; do
    delete_sandboxes_and_log
    handle_unschedulable_pods
    collect_all_pod_names
    check_node_count
    sleep 10
done

echo "ClusterLoader2 has finished."
sleep 120

# 3. Final log collection
collect_pod_logs

echo "All tasks complete at $(date)"

# 4. Calculate the metrics
cd ./metric-gathering
python extract_datetime_logs_sandbox_gcp.py gke
python calculate_benchmarks_sandbox.py gke
