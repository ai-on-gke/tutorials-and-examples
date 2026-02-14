# GKE GPU Node Reset Tool

This tool provides a Kubernetes Job definition and a helper script to manually trigger a GPU reset on a specific GKE node. This process is sometimes necessary to clear GPU issues that may not be resolved by other means.

## Prerequisites
-  **Only support A3+ GPUs**, For N1, G2, and A2 VMs you will have to [reboot the underlying compute instance](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-gpus#reset-gpus)
- Make sure there are no workload running on the node which is consuming GPUs.
-   `kubectl` installed and configured to access your GKE cluster.
-   `sed` command line utility installed.

## Files

-   `gpu-reset-job.yaml`: The Kubernetes Job manifest containing the reset logic.
-   `run.sh`: A bash script to easily apply the manifest with environment variable substitution.

## How it Works

The `gpu-reset-job.yaml` manifest defines a Kubernetes Job. When applied, this Job creates a Pod that is scheduled to run on the node specified by `NODE_NAME`. The container within the Pod executes a shell script to perform the GPU reset process. Here's a breakdown of the steps:

1.  **Initialization**:
    -   Installs necessary utilities (`bash`, `kubectl`, `jq`, etc.) in the alpine container.
    -   Sets the `TARGET_NODE` environment variable based on the Job's spec.

2.  **Pre-Reset Checks**:
    -   **Uptime Check**: Reads the node's uptime from `/proc/uptime`. If the uptime is less than or equal to `RESET_THRESHOLD_DAYS`, the script exits without performing a reset.
    -   **Last Reset Check**: Fetches the value of the `gpu-reset.gke.io/last-reset-seconds` label from the target node. If a valid timestamp is found and it's less than `RESET_THRESHOLD_DAYS` ago, the script exits. This threshold defaults to 60 days if `RESET_THRESHOLD_DAYS` is not set.

3.  **Node Preparation**:
    -   **Cordon**: Marks the node as unschedulable using `kubectl cordon [node]` to prevent new Pods from landing on it.
    -   **Taint**: Applies a taint `gpu-reset=draining:NoSchedule` to the node to and facilitate the eviction of existing Pods that don't tolerate this taint.
    -   Cordon & Taint the node (`gpu-reset=draining:NoSchedule`).
    -   Backup the current driver version label to `gpu-reset.gke.io/original-driver-version`.

4.  **Stop GPU Workloads**:
    -   Label node to remove GPU device plugin (`gke-no-default-nvidia-gpu-device-plugin=true`), waits for pod termination.
    -   Label node to stop DCGM exporter (`cloud.google.com/gke-gpu-driver-version=reset`), waits for pod termination (force deletes if needed).
    -   Sleeps to allow resource release.

5.  **GPU Reset**:
    -   Executes `/usr/local/nvidia/bin/nvidia-smi --gpu-reset`.
    -   On success, updates the `gpu-reset.gke.io/last-reset-seconds` label with the current timestamp.

6.  **Cleanup** (via `trap` and `preStop` using `/tmp/cleanup.sh`):
    -   Restore original driver label and re-enable DCGM exporter.
    -   Re-enable GPU device plugin.
    -   Uncordon the node.
    -   Remove drain taint and backup label.

## Usage

1.  **Set Environment Variables**:

    ```bash
    export NODE_NAME="your-target-node-name"
    # Optional: Override the default reset threshold (defaults to 60 days)
    # export RESET_THRESHOLD_DAYS="30" 
    ```

2.  **Run the script**:

    Navigate to the `gpu-reset-tool` directory and execute:

    ```bash
    ./run.sh
    ```

The `run.sh` script first verifies that the specified `NODE_NAME` exists in the cluster. Then, it ensures the necessary ServiceAccount and RBAC rules are in place by applying `gpu-reset-sa.yaml`. After that, it uses `sed` to substitute the `##NODE_NAME##` and `##RESET_THRESHOLD_DAYS##` placeholders in `gpu-reset-job.yaml` with the values from the environment variables and applies the job manifest to the cluster. This creates a Job with a generated name like `gpu-reset-manual-job-xxxxx`.

The script will then wait for the Pod to start, stream its logs, and finally wait for the Job to complete (up to 15 minutes), reporting whether it succeeded, failed, or timed out.

3.  **Monitor the Job and Pod**:

    The script will output the Job's final status. If the Job fails or times out, the script will attempt to fetch and display the logs from the associated Pod to help diagnose the issue.

    The Pod created by the Job will be cleaned up based on the Job's `ttlSecondsAfterFinished` setting.

## FAQ & Troubleshooting

**Q: The Job fails with status 'Error' or 'Failed'. What should I do?**

*   **Check Pod Logs**: The `run.sh` script attempts to stream logs. If that fails, manually fetch logs:
    ```bash
    kubectl logs job/<job-name> -n default
    # Or find the pod name associated with the job
    kubectl get pods -n default | grep gpu-reset-manual-job
    kubectl logs <pod-name> -n default
    ```
*   **Service Account Permissions**: Ensure the `gpu-reset-sa` ServiceAccount has the necessary ClusterRoleBindings. The `run.sh` script applies `gpu-reset-sa.yaml`, but verify it was successful.
*   **Node Existence**: Double-check that the `NODE_NAME` environment variable is set correctly and the node exists in the cluster.

**Q: The script exits early with "Uptime too low" or "Reset too recent".**

*   This is expected behavior. The script avoids unnecessary resets if the node was recently booted or reset, based on `RESET_THRESHOLD_DAYS`.
* If want to force reset, set `RESET_THRESHOLD_DAYS` to "-1".

**Q: The logs show `nvidia-smi --gpu-reset` failed.**

*   **GPU Busy**: Another process might still be using the GPU. While the script attempts to stop the device plugin and DCGM, some processes might linger. Investigate the node for other GPU-using pods.
*   **Driver Issues**: There might be an underlying problem with the NVIDIA driver installation.

**Q: The node seems stuck in a Cordoned or Tainted state.**

*   This can happen if the cleanup trap in the script doesn't execute properly (e.g., due to abrupt pod termination).
*   **Manual Cleanup**:
    ```bash
    # Uncordon
    kubectl uncordon $NODE_NAME
    # Remove Taint
    kubectl taint node $NODE_NAME gpu-reset=draining:NoSchedule-
    # Restore device plugin
    kubectl label node $NODE_NAME gke-no-default-nvidia-gpu-device-plugin-
    # Restore original driver version (if backup label exists)
    ORIGINAL_DRIVER=$(kubectl get node $NODE_NAME -o jsonpath='{.metadata.labels.gpu-reset\.gke\.io/original-driver-version}')
    if [ -n "$ORIGINAL_DRIVER" ]; then
      kubectl label node $NODE_NAME cloud.google.com/gke-gpu-driver-version=$ORIGINAL_DRIVER --overwrite
    fi
    # Remove backup label
    kubectl label node $NODE_NAME gpu-reset.gke.io/original-driver-version-
    ```

**Q: The GPU reset completed, but the original issue persists.**

*   The `nvidia-smi --gpu-reset` command can fix many soft issues, but not all. The problem might be deeper, potentially requiring a node reboot or indicating a hardware problem.

## Security Considerations

-   The Pod runs with `privileged: true` and mounts host paths, which is necessary for interacting with the node's GPU devices and drivers.
