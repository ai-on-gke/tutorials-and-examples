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

# Create a job
```bash
kubectl create -f job-autopilot.yaml
```