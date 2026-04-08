#!/bin/bash

# --- Configurations ---
KUBECONFIG_PATH=$1
CLUSTER_NAME=$2
WORKSPACE_ID=$3  # NEW: You need to pass your Azure Log Analytics Workspace ID
REPORT_DIR="./metric-gathering/test-results-aks"
CL2_DIR="${REPORT_DIR}/cl2"

# Ensure directories exist
mkdir -p "$REPORT_DIR"
mkdir -p "$CL2_DIR"

# Ensure kubeconfig is used for the current shell session
export KUBECONFIG="$KUBECONFIG_PATH"

# --- Functions ---

# Helper to find the dynamic test namespace
get_test_ns() {
    kubectl get ns -o json | jq -r '.items[] | select(.metadata.name | startswith("test-")) | .metadata.name' | head -n 1
}

CURRENT_NS=$(get_test_ns)

check_node_count() {
    # Kubernetes node status logic is universal across GKE/AKS
    kubectl get nodes -o json | jq '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True")) | .metadata.name' | wc -l >> "$REPORT_DIR/node_count.txt"
}

collect_all_pod_names() {
    FETCHED_NS=$(get_test_ns)
    CURRENT_NS=${FETCHED_NS:-$CURRENT_NS}

    [ -z "$CURRENT_NS" ] && return
    kubectl -n "$CURRENT_NS" get pods -o json | jq -c '.items[] | {pod_name: .metadata.name, creationTimestamp: .metadata.creationTimestamp}' >> "$REPORT_DIR/all_pod_names.json"
}

delete_sandboxes_and_log() {
    FETCHED_NS=$(get_test_ns)
    CURRENT_NS=${FETCHED_NS:-$CURRENT_NS}
    [ -z "$CURRENT_NS" ] && return

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
}

handle_unschedulable_pods() {
    FETCHED_NS=$(get_test_ns)
    CURRENT_NS=${FETCHED_NS:-$CURRENT_NS}
    [ -z "$CURRENT_NS" ] && return

    UNSCHEDULABLE_PODS_JSON=$(kubectl get pods -n "$CURRENT_NS" -o json | jq -c '.items[] |
        select(.status.phase == "Pending" and (.status.conditions[]? | select(.type == "PodScheduled" and .status == "False")))')

    if [ -z "$UNSCHEDULABLE_PODS_JSON" ] || [ "$UNSCHEDULABLE_PODS_JSON" == "null" ]; then
        return
    fi

    echo "$UNSCHEDULABLE_PODS_JSON" | jq -c '
        {
            pod_name: .metadata.name,
            claim_name: (.metadata.ownerReferences[0].name // "none"),
            status: .status.phase,
            reason: (.status.conditions[]? | select(.type == "PodScheduled") | .reason),
            message: (.status.conditions[]? | select(.type == "PodScheduled") | .message)
        }' >> "$REPORT_DIR/unschedulable_records.json"
}

collect_pod_logs_aks(){
    FETCHED_NS=$(get_test_ns)
    CURRENT_NS=${FETCHED_NS:-$CURRENT_NS}
    echo "[$(date +%H:%M:%S)] Starting Azure Monitor chunked log collection..."

    POD_NAMES_FILE="$REPORT_DIR/pod_names.txt"
    OUTPUT_FILE="$REPORT_DIR/all_completed_logs.json"

    if [ ! -s "$POD_NAMES_FILE" ]; then
        echo "No pods recorded. Skipping."
        return
    fi

    # Initialize output file
    echo "[]" > "$OUTPUT_FILE"

    # Azure Query logic using KQL (Kusto Query Language)
    # We target ContainerLogV2 which is the high-performance table for AKS logs
    cat "$POD_NAMES_FILE" | sort -u | xargs -L 30 | while read -r chunk; do

        # Format names for KQL 'in' operator: 'pod1', 'pod2'
        KQL_POD_LIST=$(echo "$chunk" | sed "s/ /', '/g" | sed "s/.*/'&'/")

        KQL_QUERY="ContainerLogV2
                   | where PodNamespace == '$CURRENT_NS'
                   | where PodName in ($KQL_POD_LIST)
                   | project TimeGenerated, PodName, LogMessage"

        echo "Fetching log chunk from Azure..."
        echo $KQL_QUERY
        # az monitor log-analytics query --workspace "$WORKSPACE_ID" --analytics-query "$KQL_QUERY" --format json >> "$REPORT_DIR/temp_aks_logs.json"
        az monitor log-analytics query \
            --workspace "$WORKSPACE_ID" \
            --analytics-query "$KQL_QUERY" \
            --output json >> "$REPORT_DIR/temp_aks_logs.json"
    done

    # Merge results into one valid JSON array
    if [ -f "$REPORT_DIR/temp_aks_logs.json" ]; then
        jq -s 'add' "$REPORT_DIR/temp_aks_logs.json" > "$OUTPUT_FILE"
        rm "$REPORT_DIR/temp_aks_logs.json"
        echo "Logs saved to $OUTPUT_FILE"
    fi
}

# --- Main Execution ---

echo "Starting ClusterLoader2 for AKS at $(date)"

# 1. Start ClusterLoader (changed provider to aks)
./perf-tests/clusterloader2/clusterloader2 \
  --testconfig="./aks-templates/config.yaml" \
  --provider=aks \
  --kubeconfig="$KUBECONFIG_PATH" \
  --v=2 \
  --report-dir="$CL2_DIR" &

CL2_PID=$!

while ps -p $CL2_PID > /dev/null; do
    delete_sandboxes_and_log
    handle_unschedulable_pods
    collect_all_pod_names
    check_node_count
    sleep 10
done

echo "ClusterLoader2 finished. Collecting logs..."
sleep 120
collect_pod_logs_aks

# 4. Metrics Calculation
cd ./metric-gathering
python extract_datetime_logs_sandbox_aks.py aks
python calculate_benchmarks_sandbox.py aks

echo "Benchmark complete."
