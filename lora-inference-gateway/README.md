# GKE Inference Gateway for Multi-Model Serving

This guide provides comprehensive instructions for deploying a GKE Inference Gateway to serve multiple AI models using the VLLM inference server.

## Overview & Architecture

The **GKE Inference Gateway** is a managed, high-performance solution for deploying and managing AI/ML inference workloads on GKE. It provides a single, stable entry point (an Internal Load Balancer) to route requests to multiple, independently deployed models. This architecture is ideal for production environments as it simplifies client configuration, centralizes access control, and leverages GKE's native capabilities for autoscaling and GPU management.

The implementation follows a clear, three-tiered architecture:

1.  **GPU Node Pool (`inference-pool.yaml`)**: A dedicated GKE `NodePool` is provisioned with NVIDIA L4 GPUs. It is configured to autoscale and can scale down to zero nodes when not in use, providing significant cost savings. All model inference pods are scheduled exclusively on this pool.

2.  **Model Deployments & Services (`vllm-deployment.yaml`, `vllm-service.yaml`)**: The VLLM inference server is deployed as a separate Kubernetes `Deployment`. This isolates the workload, allowing it to be scaled and updated independently. The `Deployment` is exposed internally by a `ClusterIP` `Service`, which provides a stable network endpoint for the gateway to target.

3.  **Inference Gateway and Models (`gateway.yaml`, `httproute.yaml`, `inference-model.yaml`)**: The `InferenceGateway` custom resource is the core of this architecture. It automatically provisions a Google Cloud Internal Load Balancer, and the `HTTPRoute` resource defines the routing rules. The `InferenceModel` custom resources define the specific models to be served, allowing for dynamic management. The gateway inspects the request path and forwards traffic to the appropriate backend `Service`.

---
## LoRA and Efficient Multi-Model Serving

A key feature of this setup is the use of **Low-Rank Adaptation (LoRA)** to serve multiple specialized models efficiently. Instead of deploying a full, separate large language model for each task, we load a single base model into GPU memory and then apply lightweight "adapters" for each specific use case.

### What is LoRA?

LoRA (Low-Rank Adaptation) is a parameter-efficient fine-tuning (PEFT) technique that significantly reduces the cost and complexity of adapting large language models to new tasks. Instead of retraining all of a model's billions of parameters, LoRA freezes the original weights and injects small, trainable matrices into the model's architecture. These matrices, or "adapters," are the only components that are updated during fine-tuning.

The key benefits of this approach are:

*   **Reduced Computational Cost**: Training only the small adapter matrices is significantly faster and requires less GPU memory than full model fine-tuning.
*   **Smaller Model Artifacts**: LoRA adapters are typically only a few megabytes in size, compared to the gigabytes required for a full model. This makes them easier to store, manage, and distribute.
*   **Efficient Task Switching**: Since the base model remains in memory, you can switch between different tasks by simply swapping out the lightweight LoRA adapters, which is much faster than loading a new large model.

### LoRA in This Project

This project demonstrates the power of LoRA for multi-model serving. Here’s how it works:

1.  **Base Model**: The `vllm-deployment.yaml` specifies a base model (`google/gemma-3-1b-it`) that is loaded into the VLLM inference server. This is the large, general-purpose model that resides in GPU memory.
2.  **LoRA Adapters**: The `ConfigMap` named `vllm-gemma3-1b-adapters` defines the LoRA adapters that will be applied to the base model. In this case, it defines the `sql-chat` model, which is a fine-tuned adapter for converting natural language to SQL queries.
3.  **Dynamic Loading**: The `lora-adapter-syncer` init container reads this `ConfigMap` and ensures that the specified LoRA adapters are downloaded and made available to the VLLM server.
4.  **Inference Requests**: When you make a request to the gateway and specify the `sql-chat` model, the VLLM server applies the corresponding LoRA adapter to the base Gemma model on the fly to generate the response. A request for the base model (`google/gemma-3-1b-it`) will use the unmodified base model.

This architecture allows you to serve a base model and numerous specialized, fine-tuned models from a single GPU, dramatically improving resource utilization and reducing operational costs.

---

## Deployment Guide

### 1. Prerequisites
Before you begin, ensure you have completed the environment setup instructions in [SETUP.md](SETUP.md). This includes:
*   Installing `gcloud` and `kubectl`.
*   Creating and configuring a Google Cloud project.
*   Creating a GKE cluster with the Inference Gateway enabled.
*   Configuring a Hugging Face access token.

### 2. Deploy the Inference Infrastructure

#### Create the GPU Node Pool
This manifest provisions the necessary GPU hardware for the inference workloads.

```bash
kubectl apply -f inference-pool.yaml
```

#### Deploy the VLLM Inference Server
Deploy the VLLM inference server, which includes the Deployment and Service.

```bash
kubectl apply -f vllm-deployment.yaml
kubectl apply -f vllm-service.yaml
```

#### Deploy the Inference Gateway and Routing
This manifest creates the InferenceGateway, the associated HTTPRoute for routing, and the inference models.

```bash
kubectl apply -f gateway.yaml
kubectl apply -f httproute.yaml
kubectl apply -f inference-model.yaml
```

### 3. Verify and Test

Before sending test requests, verify that all components have been deployed and initialized successfully.

**1. Check the VLLM Pod Status**

Check the status of the VLLM deployment to ensure the pods are running.

```bash
kubectl get pods -l app=gemma-server
```

Wait until the pod status is `Running`. If the status is `ImagePullBackOff` or `ErrImagePull`, there may be an issue with the image registry or node networking. If the pod is `CrashLoopBackOff`, use `kubectl logs <pod-name>` to inspect the logs for errors.

> **Note on Health Checks and Gateway Routing:** The GKE Gateway will not send traffic to the VLLM pods until they are fully running *and* their readiness probe is passing. The `readinessProbe` is configured in `vllm-deployment.yaml` and is essential for signaling to the gateway that the model is loaded and ready to serve inference requests. The `initialDelaySeconds` is intentionally set to a high value (300 seconds) to give the server enough time to download and load the large model into GPU memory. If you send requests before the readiness probe passes, you may receive HTTP 5xx errors from the gateway.

**2. Verify Gateway Configuration**

Check that the `HTTPRoute` and `InferenceModel` resources have been accepted by the gateway.

*   **Check the HTTPRoute:**
    ```bash
    kubectl get httproute vllm-gemma-route -o yaml
    ```
    Look for a `condition` of type `Accepted` with `status: "True"` in the `status` field. This confirms the gateway is managing the route.

*   **Check the InferenceModels:**
    ```bash
    kubectl get inferencemodel -o yaml
    ```
    Ensure both `base-gemma-model` and `sql-chat` models have a `condition` in their `status` field indicating they are `Ready` or `Accepted`.

**3. Verify the Service is Active**

Confirm that the `llm-service` is active and has been assigned a `CLUSTER-IP`.

```bash
kubectl get service llm-service
```

**4. Get the Gateway IP Address**

It may take a few minutes for the load balancer to be provisioned. Check the status and get the IP address with the following command:

```bash
GATEWAY_IP=$(kubectl get gateway ai-inf-gateway -o jsonpath='{.status.addresses[0].value}')
echo "Gateway IP: $GATEWAY_IP"
```

If the command returns an empty string, wait a few minutes and try again.

**5. Test the Endpoints**

Once the gateway has an IP address, you can send inference requests to each model from a VM or pod within the same VPC network.

**Test the base Gemma model:**

```bash
curl http://${GATEWAY_IP}/v1/chat/completions \
  -X POST \
  -H "Content-Type: application/json" \
  -d 
'{ 
    "model": "google/gemma-3-1b-it",
    "messages": [
      {
        "role": "user",
        "content": "What is the meaning of life?"
      }
    ]
  }'
```

**Test the SQL Chat LoRA model:**

```bash
curl http://${GATEWAY_IP}/v1/chat/completions \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{ "model": "sql-chat", "messages": [ { "role": "user", "content": "List the three largest cities in Texas by population." } ] }'
```

Since `sql-chat` is a text-to-SQL model, the expected response will not be the list of cities, but rather the SQL query that would retrieve them. The model's output in the JSON response should contain a query similar to this:
```sql
SELECT city, population FROM cities WHERE state = 'Texas' ORDER BY population DESC LIMIT 3;
```

A successful response will be a JSON object containing the model's output.

## Cleanup

To avoid incurring ongoing charges, you can delete the resources you created.

#### 1. Delete the Kubernetes Resources:

```bash
kubectl delete -f gateway.yaml
kubectl delete -f httproute.yaml
kubectl delete -f inference-model.yaml
kubectl delete -f vllm-service.yaml
kubectl delete -f vllm-deployment.yaml
```

#### 2. Delete the GPU Node Pool:

```bash
# The CLUSTER_NAME and REGION variables should still be set
gcloud container node-pools delete inference-pool \
  --cluster ${CLUSTER_NAME} \
  --region=${REGION}
```