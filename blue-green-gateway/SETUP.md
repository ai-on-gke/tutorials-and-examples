# Environment Setup Guide

This guide provides detailed, step-by-step instructions for setting up your Google Cloud and Kubernetes environment to run the AI inference workloads described in the `README.md`.

## 1. Tool Installation

Install and configure the following command-line tools.

#### Google Cloud CLI
Install and initialize the [Google Cloud CLI (`gcloud`)](https://cloud.google.com/sdk/docs/install). This is essential for interacting with your Google Cloud project.

#### kubectl
Install the Kubernetes command-line tool, `kubectl`. The `gcloud` CLI can install it for you:
```bash
gcloud components install kubectl
```

## 2. Google Cloud Project Setup

It is highly recommended to use a new, dedicated Google Cloud project to avoid conflicts with existing resources.

The following script sets up environment variables and creates a new project.

```bash
# Set your GCP username and desired region
export USERNAME=${USER}
export PROJECT_ID="k8sai-${USERNAME}"
export REGION="us-central1" # A region with good GPU availability

# Set your organization or folder ID and billing account
export GCP_ORG="YOUR_ORG_ID" # Or use GCP_FOLDER="YOUR_FOLDER_ID"
export GCP_BILLING="YOUR_BILLING_ACCOUNT" # e.g., 000000-000000-000000
export ADMINUSER=$(gcloud config get-value account)

# Create a separate gcloud configuration to avoid conflicts
gcloud config configurations create k8sai-blue-green
gcloud config set account ${ADMINUSER}
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}

# Create the project
# Use --organization or --folder depending on your setup
gcloud projects create ${PROJECT_ID} --organization=${GCP_ORG}
# gcloud projects create ${PROJECT_ID} --folder=${GCP_FOLDER}

# Link the billing account to the new project
gcloud beta billing projects link ${PROJECT_ID} --billing-account ${GCP_BILLING}

# Set the new project for application default credentials
gcloud auth application-default set-quota-project ${PROJECT_ID}

echo "GCP project ${PROJECT_ID} created and configured."
```
> **Note:** The region is set to `us-central1` as it generally offers good availability of various GPU resources. However, you should always verify the [Google Cloud documentation for regional availability](https://cloud.google.com/compute/docs/gpus/gpu-regions-zones) of specific accelerators.

### IAM Permissions
Ensure your user account has the necessary IAM roles to create and manage GKE clusters and related resources, such as `roles/resourcemanager.projectCreator`, `roles/billing.user`, `roles/compute.admin`, `roles/container.admin`, and `roles/iam.serviceAccountAdmin`.

## 3. Enable Google Cloud APIs

Enable the APIs required for GKE:
```bash
gcloud services enable \
  container.googleapis.com \
  cloudresourcemanager.googleapis.com
```

## 4. Create a GKE Autopilot Cluster

This project uses a GKE Autopilot cluster, which automatically provisions and manages the underlying nodes, including GPUs.

```bash
export CLUSTER_NAME="blue-green-cluster"

gcloud container clusters create-auto ${CLUSTER_NAME} \
    --region=${REGION}
```

### Configure `kubectl`
Point `kubectl` to your new cluster:
```bash
gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION}
```

## 5. Configure Model Access

To download models from Hugging Face, you need to provide an access token.

### Hugging Face Access
1.  **Create a Hugging Face account** and [generate an access token](https://huggingface.co/docs/hub/en/security-tokens) with at least 'Read' permissions.
2.  **Create a Kubernetes secret** with your token in the `default` namespace. The deployment manifest expects the secret to be named `hf-secret`.
    ```bash
    export HF_TOKEN="your-hugging-face-token" # Replace with your token
    kubectl create secret generic hf-secret \
       --namespace=default \
       --from-literal=hf_token=$HF_TOKEN
    ```

Your environment is now fully set up. You can proceed to the main `README.md` to deploy the inference services.

## 6. Cleanup

To avoid incurring ongoing charges, you can delete the resources you created.

**DANGER:** The following command will permanently delete your Google Cloud project and all resources within it.

```bash
# The PROJECT_ID variable should still be set from the setup steps
gcloud projects delete ${PROJECT_ID} --quiet

# Delete the gcloud configuration
gcloud config configurations activate default
gcloud config configurations delete k8sai-blue-green

# Delete the kubectl context
kubectl config delete-context \
  "gke_${PROJECT_ID}_${REGION}_${CLUSTER_NAME}"
```