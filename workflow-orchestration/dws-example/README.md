# Dynamic Workload Scheduler examples

>[!NOTE]
>This repository provides the files needed to demonstrate how to use [Kueue](https://kueue.sigs.k8s.io/) with [Dynamic Workload Scheduler](https://cloud.google.com/blog/products/compute/introducing-dynamic-workload-scheduler?e=48754805) (DWS) and [GKE Autopilot](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview). 



# Setup and Usage

## Prerequisites
- [Google Cloud](https://cloud.google.com/) account set up.
- [gcloud](https://pypi.org/project/gcloud/) command line tool installed and configured to use your GCP project.
- [kubectl](https://kubernetes.io/docs/tasks/tools/) command line utility is installed.
- [terraform](https://developer.hashicorp.com/terraform/install) command line installed.

## Create Clusters

```bash
terraform -chdir=tf init
terraform -chdir=tf plan
terraform -chdir=tf apply -var project_id=<YOUR PROJECT ID>
```

## Install Kueue


```bash
VERSION=v0.12.0
kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/$VERSION/manifests.yaml
```

# Create Kueue resources

```bash
kubectl apply -f dws-queues.yaml 
```

### Validate installation

Verify the Kueue installation in your GKE cluster

```bash
kubectl get clusterqueues dws-cluster-queue -o jsonpath="{range .status.conditions[?(@.type == \"Active\")]}CQ - Active: {@.status} Reason: {@.reason} Message: {@.message}{'\n'}{end}"
kubectl get admissionchecks dws-prov -o jsonpath="{range .status.conditions[?(@.type == \"Active\")]}AC - Active: {@.status} Reason: {@.reason} Message: {@.message}{'\n'}{end}"

```

If the installation and configuration were successful, you should see the following output:

```bash
CQ - Active: True Reason: Ready Message: Can admit new workloads
AC - Active: True Reason: Active Message: The admission check is active
```

# Create a job
```bash
kubectl create -f job-autopilot.yaml
```

# How Kueue and DWS work

After creating the job, you can review the provisioning request:

```bash
kubectl get provisioningrequests
```

You should see output similar to this:

```bash
NAME                                 ACCEPTED   PROVISIONED   FAILED   AGE
sample-dws-job-bq9r9-9409b-dws-prov-1   True       False                   158m
```

Kueue creates the provisioning request, which is integrated with DWS. If DWS receives and accepts the request, the ACCEPTED value will be True. Then, as soon as DWS can secure access to your resources, the PROVISIONED value will change to TRUE. At that point, the node is created, and the job schedules on that node. Once the job finishes, GKE automatically releases the node.


```bash
kubectl get provisioningrequests
kubectl get nodes
kubectl get job
```