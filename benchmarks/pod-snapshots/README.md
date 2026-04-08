# Kubernetes Pod Startup Benchmarking for vLLM

## Overview

This framework measures and compares real-world pod startup latency for vLLM workloads on Kubernetes. It targets AI inference workloads where cold start time directly impacts scaling SLOs.

Use this to:
- Establish a startup time baseline for vLLM on GPU nodes
- Compare optimization techniques side by side (e.g. RunAI model streamer, GKE Pod Snapshots)
- Identify bottlenecks across scheduler, image pull, and application warmup phases
- Validate infrastructure changes across cloud providers

---

## Repository structure

```
.
├── terraform/              # Cloud infrastructure (GCP, AWS, Azure)
├── images/
│   └── exporter/           # Prometheus exporter source (measures pod readiness)
├── charts/
│   └── exporter/           # Helm chart to deploy the exporter
├── tests/
│   ├── baseline/           # Plain vLLM deployment, no optimizations
│   ├── runai_streamer/     # vLLM with RunAI model streamer
│   └── snapshots/          # GKE Pod Snapshots (GKE-only)
└── pod_snapshots/          # Script and manifests to enable GKE Pod Snapshots
```

---

## Prerequisites

Make sure the following tools are installed and authenticated before proceeding:

| Tool | Purpose |
|---|---|
| `terraform` | Provision cloud infrastructure |
| `kubectl` | Manage Kubernetes resources |
| `helm` | Deploy the exporter chart |
| `docker` | Build and push container images |
| `gcloud` / `aws` / `az` | Cloud provider CLI |

You will also need:
- A [Hugging Face](https://huggingface.co) account with a valid API token that has access to `Qwen/Qwen3-32B`
- Sufficient GPU quota in your cloud project (H100 recommended for `Qwen3-32B`)

---

## Step 1 — Provision infrastructure
    
1. Specify an environment variable with huggingface token that will be passed as a terraform variable:
   ```sh
   export TF_VAR_hf_token="<YOUR_HF_TOKEN>"
   ```

2. Specify the 'CLOUD_PROVIDER' environment variable:
   ```sh
   CLOUD_PROVIDER=gcp
   ```

3. Set a shorthand for the Terraform command:
   ```sh
   TERRAFORM_CMD="terraform -chdir=./terraform/${CLOUD_PROVIDER}"
   ```

4. Initialize the terraform configuration:
   ```sh
   $TERRAFORM_CMD init
   ```

5. Apply the terraform config just for the cluster.
   ```sh
   $TERRAFORM_CMD apply -var-file ../common.tfvars -var-file values.tfvars -target=terraform_data.ready_cluster
   ```

6. Make current terminal session use previously created kubeconfig file:
   ```sh
   export KUBECONFIG="./kubeconfig_${CLOUD_PROVIDER}"
   ```

7. Create kubeconfig file for the created cluster:
   ```sh
   gcloud container clusters get-credentials \
     $($TERRAFORM_CMD output -raw cluster_name) \
     --location $($TERRAFORM_CMD output -raw cluster_location)
   ```

8. Apply the rest of the terraform config:
   ```sh
   $TERRAFORM_CMD apply -var-file ../common.tfvars -var-file values.tfvars
   ```

For AWS and Azure, refer to the provider-specific guides:
- [AWS setup](./docs/infra/aws.md)
- [Azure setup](./docs/infra/azure.md)
- [GCP setup](./docs/infra/gcp.md)


## Step 2 — Build and deploy the exporter

1. The exporter is a Prometheus metrics server that measures pod startup time in three phases. It must be deployed before running any tests.

   ```sh
   helm upgrade --install exporter ./charts/exporter \
     --set "image.imageName=$($TERRAFORM_CMD output -raw exporter_image)"
   ```

2. Once deployed, expose the metrics endpoint, better in another terminal session, but in the same current directory:

   ```sh
   CLOUD_PROVIDER="<gcp or aws or azure>"
   export KUBECONFIG="./kubeconfig_${CLOUD_PROVIDER}"
   kubectl port-forward service/exporter 8080:8080
   ```

Metrics are available at `http://localhost:8080/metrics`.


## Step 3 — Run a test

Choose one of the test scenarios below. Each deploys a vLLM instance with a different startup strategy. After a pod becomes Ready, scrape the exporter to see its startup latency.

### Reading results

```sh
curl -s localhost:8080/metrics | grep vllm
```

You will see three metrics per pod:

| Metric | What it measures |
|---|---|
| `k8s_pod_created_to_ready_seconds` | Total end-to-end time: creation → Ready |
| `k8s_pod_scheduled_to_ready_seconds` | Node-side time: scheduled → Ready (includes image pull) |
| `k8s_pod_startup_seconds` | App warmup only: container running → Ready |

See the source code for the exporter in `limages/exporter` to get more info.

---

### Test: Baseline

A standard vLLM deployment with no startup optimizations. Use this as your reference point.

1. Apply the kustomization folder:

   ```sh
   kubectl apply -k tests/baseline/overlays/${CLOUD_PROVIDER}
   ```

2. Wait until pods are Ready:

   ```sh
   kubectl rollout status deployment/vllm-baseline --timeout=600s
   ```

3. The relevant metrics can be later fetched with curl:
   ```sh
   curl -s localhost:8080/metrics | grep vllm
   ```

### Test: RunAI Model Streamer

vLLM configured to load model weights using the RunAI model streamer (`--load-format=runai_streamer`). This enables parallel and distributed weight loading, which can significantly reduce startup time for large models.


1. Apply the kustomization folder:

   ```sh
   kubectl apply -k tests/runai_streamer/overlays/${CLOUD_PROVIDER}
   ```

2. Wait until pods are Ready:

   ```sh
   kubectl rollout status deployment/vllm-streamer --timeout=600s
   ```

3. The relevant metrics can be later fetched with curl:
   ```sh
   curl -s localhost:8080/metrics | grep vllm
   ```

### Test: GKE Pod Snapshots

> ⚠️ **GKE only.** This test requires Google Kubernetes Engine with gVisor and the Pod Snapshots operator. It will not work on other providers.

Pod Snapshots checkpoint a running pod's memory state to GCS, then restore new pods directly from that snapshot — bypassing model loading entirely. The workflow has three phases.

#### Phase 1: Create a snapshot

1. Create a `PodSnapshotStorageConfig` by applying the corresponding kustomization folder:
   ```sh
   kubectl apply -k tests/snapshots/pod-storage-config/overlays/${CLOUD_PROVIDER}
   ```

2. Create a `PodSnapshotPolicy`:
   ```sh
   kubectl apply -f tests/snapshots/policy.yaml
   ```

3. Deploy vLLm:
   ```sh
   kubectl apply -k tests/snapshots/vllm-pod-snapshots/overlays/${CLOUD_PROVIDER}
   ```

4. Wait for deployment is ready:
   ```sh
   kubectl rollout status deployment/vllm-pod-snapshots --timeout=600s
   ```

5. Pick a pod to snapshot and save its name into variable:
   ```sh
   POD_TO_SNAPSHOT_NAME="<NAME>"
   ```

6. Trigger creation of a snapshot by applying the following manifest:
   ```sh
   kubectl apply -f - <<-EOF
   apiVersion: podsnapshot.gke.io/v1alpha1
   kind: PodSnapshotManualTrigger
   metadata:
     name: vllm-pod-snapshots-snapshot-01 # MUST BE UNIQUE NAMESPACE-WIDE !!!
     namespace: default
   spec:
     targetPod: "${POD_TO_SNAPSHOT_NAME}"
   EOF
   ```

7. Wait for the snapshot to complete and retrieve its UUID:

   ```sh
   kubectl get podsnapshot.podsnapshot.gke.io
   # Note the NAME/UUID from the output
   ```

#### Phase 2: Benchmark restore from snapshot

1. Patch the deployment to use the snapshot UUID, then cycle replicas. New pods will restore from the snapshot instead of loading model weights from scratch:

   ```sh
   export SNAP=YOUR_SNAPSHOT_UUID
   
   kubectl patch deployment vllm-pod-snapshots -n default --type merge \
     -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"podsnapshot.gke.io/ps-name\":\"$SNAP\"}}}}}"
   
   # Force a pod cycle — the new pod will restore from the snapshot
   kubectl scale deployment vllm-pod-snapshots --replicas 0
   kubectl scale deployment vllm-pod-snapshots --replicas 1
   ```

2. Wait until the pod is Ready, then check metrics:

   ```sh
   kubectl port-forward service/exporter 8080:8080
   curl -s localhost:8080/metrics | grep vllm
   ```

---

## Key differences between test manifests

| | Baseline | RunAI Streamer | Pod Snapshots |
|---|---|---|---|
| GPU selector | Any (taint toleration only) | `nvidia-l4` explicit | Any (gVisor taint required) |
| Service type | LoadBalancer | ClusterIP | LoadBalancer |
| Container runtime | Standard | Standard | gVisor (required) |
| Readiness probe path | `/v1/models` | `/health` | `/v1/models` |
| Cloud support | All | All | GKE only |

---

## Notes and known issues

- **`take_snap.yaml` trigger name must be unique namespace-wide.** If you re-run the snapshot step, change `metadata.name` on the `PodSnapshotManualTrigger` resource to a new value before applying.
- **The baseline manifest includes a `dev.gvisor.internal.nvproxy: "true"` annotation** even though it does not schedule on gVisor nodes. This annotation is safe to remove for non-gVisor deployments.
- **For accurate measurements**, keep `initialDelaySeconds` low (baseline and snapshots tests use `1`) and `failureThreshold` high so probe retries do not interfere with timing.


## Exported Metrics

### `k8s_pod_startup_seconds`
**Container start → Ready**

The time from when the first container actually started running to when the pod passed its readiness probe. This is pure **application warmup time** — image is already pulled, container runtime is up. Use this to measure how long your app takes to initialize.

---

### `k8s_pod_scheduled_to_ready_seconds`
**Scheduled → Ready**

The time from when the pod was assigned to a node to when it became Ready. This covers **node-side work**: image pull, container runtime startup, and app warmup. High values here (vs `startup_seconds`) point to slow image pulls or a cold node.

---

### `k8s_pod_created_to_ready_seconds`
**Created → Ready**

The full end-to-end time from pod object creation to Ready. Includes everything above **plus** scheduler latency and any time the pod spent pending (e.g. waiting for resources, node autoscaling). This is your true "how long did my workload take to come up" SLO metric.

---

## Phase breakdown

```
Pod created ──► Scheduled ──► Containers started ──► Ready
│◄────────────────────────────────────────────────────►│  created_to_ready
              │◄────────────────────────────────────────►│  scheduled_to_ready
                            │◄───────────────────────────►│  startup_seconds (app warmup)
```

---

## Labels

All metrics share the same label set:

| Label | Description |
|---|---|
| `namespace` | Pod namespace |
| `pod` | Pod name |
| `owner` | Owning resource name (e.g. Deployment name) |
| `owner_kind` | `Deployment`, `StatefulSet`, `DaemonSet`, `Job`, or `standalone` |

---


Metrics are exposed at `:8080/metrics` in standard Prometheus text format.
