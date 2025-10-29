# Autoscaling AI Inference on GKE with vLLM and Gemma

This guide provides a comprehensive walkthrough for deploying a vLLM-powered AI inference server for the Gemma model on Google Kubernetes Engine (GKE) Autopilot and configuring Horizontal Pod Autoscaling (HPA) to automatically scale the deployment based on demand.

You will learn how to:

*   Deploy a vLLM server for the Gemma model on GKE Autopilot.
*   Configure HPA to automatically scale the server based on two different strategies:
    1.  **vLLM Server Metrics:** Scale based on the number of concurrent requests.
    2.  **NVIDIA GPU Metrics:** Scale based on GPU utilization.
*   Test the autoscaling functionality with a load generation script.

## 1. Prerequisites

This section covers the one-time setup required to prepare your environment.

### Step 1: Set Environment Variables

Set the following environment variables in your shell.

```bash
# Replace with your actual project ID
export PROJECT_ID="your-project-id"

# GKE cluster name
export CLUSTER_NAME="vllm-gemma-cluster"

# Google Cloud region
export REGION="us-central1"

# Hugging Face access token
export HF_TOKEN="your-hugging-face-token"

# The model to deploy
export MODEL_ID="google/gemma-2b-it"
```

### Step 2: Configure Google Cloud

1.  Select or create a [Google Cloud project](https://console.cloud.google.com/projectcreate).
2.  Ensure [billing is enabled](https://cloud.google.com/billing/docs/how-to/modify-project).
3.  Enable the **Kubernetes Engine API**:
    ```bash
    gcloud services enable container.googleapis.com
    ```
4.  Ensure you have `Kubernetes Engine Admin` IAM permissions.

### Step 3: Install Tools

1.  **Google Cloud CLI (`gcloud`):** Install the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install-sdk) and initialize it:
    ```bash
    gcloud init
    ```
2.  **`kubectl`:** Install via `gcloud`:
    ```bash
    gcloud components install kubectl
    ```

### Step 4: Get Hugging Face Token

1.  Create a [Hugging Face account](https://huggingface.co/join).
2.  Accept the license for your chosen model (e.g., [google/gemma-2b-it](https://huggingface.co/google/gemma-2b-it)).
3.  Generate an [access token](https://huggingface.co/docs/hub/en/security-tokens) with 'Read' permissions.

### Step 5: Create GKE Cluster and Kubernetes Secret

1.  Create the GKE Autopilot cluster:
    ```bash
    gcloud container clusters create-auto $CLUSTER_NAME \
        --project=$PROJECT_ID \
        --region=$REGION
    ```
2.  Connect `kubectl` to your new cluster:
    ```bash
    gcloud container clusters get-credentials $CLUSTER_NAME \
        --region=$REGION \
        --project $PROJECT_ID
    ```
3.  Create the Kubernetes secret for your Hugging Face token:
    ```bash
    kubectl create secret generic hf-secret \
        --from-literal=hf_token=$HF_TOKEN
    ```

## 2. Deploy the vLLM Server

This section covers the deployment of the vLLM server and service.

### Step 1: Deploy the vLLM Server

Apply the deployment manifest to your GKE cluster.

```bash
kubectl apply -f vllm-deployment.yaml
```

### Step 2: Expose the Service

Apply the service manifest to expose the vLLM deployment within the cluster.

```bash
kubectl apply -f vllm-service.yaml
```

### Step 3: Monitor the Deployment

Monitor the pod status until it is `Running`.

```bash
# Watch the pods until they are in the "Running" state
kubectl get pods -l app=vllm-gemma-server -w

# (Optional) Wait for the deployment to be fully available
kubectl wait --for=condition=Available --timeout=900s deployment/vllm-gemma-deployment
```

### Step 4: Test the Endpoint

Use `kubectl port-forward` to access the service from your local machine.

```bash
# In a new terminal, forward local port 8080 to the service's port 8081
kubectl port-forward service/vllm-service 8080:8081
```

With port forwarding active, send an inference request using `curl`:

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
-H "Content-Type: application/json" \
-d 
    "{
        \"model\": \"$MODEL_ID\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Explain Quantum Computing in simple terms.\"}]
    }"
```

## 3. Configure Autoscaling

This section details the two methods for autoscaling the vLLM server.

### Step 1: Deploy and Configure the Stackdriver Adapter

The Custom Metrics Stackdriver Adapter is required for both autoscaling strategies.

1.  **Apply the manifest:**
    ```bash
    kubectl apply -f ./stack-driver-adapter.yaml
    ```

2.  **Verify the deployment:**
    ```bash
    kubectl get pods -n custom-metrics
    ```

3.  **Grant Permissions with Workload Identity:**
    ```bash
    # 1. Create a dedicated Google Service Account (GSA) for the adapter
    gcloud iam service-accounts create metrics-adapter-gsa \
      --project=${PROJECT_ID} \
      --display-name="Custom Metrics Stackdriver Adapter GSA"

    # 2. Grant the GSA the "Monitoring Viewer" role
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
      --member="serviceAccount:metrics-adapter-gsa@${PROJECT_ID}.iam.gserviceaccount.com" \
      --role="roles/monitoring.viewer"

    # 3. Create an IAM policy binding between the GSA and the Kubernetes Service Account (KSA)
    gcloud iam service-accounts add-iam-policy-binding \
      metrics-adapter-gsa@${PROJECT_ID}.iam.gserviceaccount.com \
      --project=${PROJECT_ID} \
      --role="roles/iam.workloadIdentityUser" \
      --member="serviceAccount:${PROJECT_ID}.svc.id.goog[custom-metrics/custom-metrics-stackdriver-adapter]"

    # 4. Annotate the Kubernetes Service Account
    kubectl annotate serviceaccount \
      custom-metrics-stackdriver-adapter \
      --namespace custom-metrics \
      iam.gke.io/gcp-service-account=metrics-adapter-gsa@${PROJECT_ID}.iam.gserviceaccount.com
    ```

### Step 2: Choose a Scaling Strategy

#### Option A: Scale with vLLM Server Metrics

This method scales the server based on the number of concurrent requests.

1.  **Apply the `PodMonitoring` Manifest:**
    ```bash
    kubectl apply -f ./pod-monitoring.yaml
    ```

2.  **Deploy the Horizontal Pod Autoscaler:**
    ```bash
    kubectl apply -f ./horizontal-pod-autoscaler.yaml
    ```

3.  **Verify the HPA's Status:**
        ```bash
            kubectl describe hpa gemma-server-hpa    ```

#### Option B: Scale with NVIDIA GPU Metrics

This method scales the server based on GPU utilization.

1.  **Apply the Monitoring Configuration:**
    ```bash
    kubectl apply -f ./gpu-pod-monitoring.yaml
    kubectl apply -f ./gpu-rules.yaml
    ```

2.  **Deploy the Horizontal Pod Autoscaler:**
    ```bash
    kubectl apply -f ./gpu-horizontal-pod-autoscaler.yaml
    ```

3.  **Verify the HPA's Status:**
    ```bash
    kubectl describe hpa gemma-server-gpu-hpa
    ```

## 4. Test Autoscaling

Generate a sustained load on the inference server to trigger an autoscaling event.

1.  **Expose the Service Locally:**
    ```bash
    kubectl port-forward service/llm-service 8081:8081
    ```

2.  **Start the Load Generator:**
    In a new terminal, run the `request-looper.sh` script.
    ```bash
    ./request-looper.sh
    ```

3.  **Observe the Scaling Behavior:**
    ```bash
    # Watch the HPA's status (replace with the correct HPA name)
    kubectl describe hpa gemma-server-hpa

    # In another terminal, watch the number of deployment replicas increase
    kubectl get deploy/vllm-gemma-deployment -w
    ```

## 5. Cleanup

To avoid ongoing charges, delete the resources you created.

```bash
# Delete HPA resources (if deployed)
kubectl delete hpa gemma-server-hpa
kubectl delete hpa gemma-server-gpu-hpa
kubectl delete -f ./stack-driver-adapter.yaml
kubectl delete namespace custom-metrics
kubectl delete podmonitoring/gemma-pod-monitoring
kubectl delete -f ./gpu-pod-monitoring.yaml
kubectl delete -f ./gpu-rules.yaml

# Delete Kubernetes resources
kubectl delete service vllm-service
kubectl delete deployment vllm-gemma-deployment
kubectl delete secret hf-secret

# Delete the GKE cluster
gcloud container clusters delete $CLUSTER_NAME \
    --region=$REGION \
    --project $PROJECT_ID
```

## 6. Troubleshooting

*   **Pod is stuck in `Pending` state:** This is likely due to a lack of available GPU resources. Check the pod's events for messages about resource constraints: `kubectl describe pod <pod-name>`.
*   **HPA is not scaling:**
    *   Verify that the HPA can see the metric: `kubectl describe hpa <hpa-name>`.
    *   Check the logs of the Stackdriver Adapter for errors: `kubectl logs -n custom-metrics -l k8s-app=custom-metrics-stackdriver-adapter`.
*   **Inference requests are failing:** Check the logs of the vLLM server for errors: `kubectl logs -l app=vllm-gemma-server`.
