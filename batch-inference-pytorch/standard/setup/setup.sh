# Copyright 2025 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
#set -e

# Load the environment variables from the .env file
source .env

echo "✅ Environment variables loaded. Starting setup for project: ${PROJECT}"

################################################################################
#                                                                              #
#                               NETWORK SETUP                                  #
#                                                                              #
################################################################################

echo "🚀 Starting Network Setup..."

# Create a VPC for the gVNIC NIC
echo "Creating gVNIC VPC..."
gcloud compute --project=${PROJECT} \
  networks create \
  ${GVNIC_NETWORK_PREFIX}-net \
  --subnet-mode=custom

gcloud compute --project=${PROJECT} \
  networks subnets create \
  ${GVNIC_NETWORK_PREFIX}-sub \
  --network=${GVNIC_NETWORK_PREFIX}-net \
  --region=${REGION} \
  --range=192.168.0.0/24

gcloud compute --project=${PROJECT} \
  firewall-rules create \
  ${GVNIC_NETWORK_PREFIX}-internal \
  --network=${GVNIC_NETWORK_PREFIX}-net \
  --action=ALLOW \
  --rules=tcp:0-65535,udp:0-65535,icmp \
  --source-ranges=192.168.0.0/16

# Create HPC VPC for the RDMA NICs
echo "Creating RDMA VPC..."
gcloud beta compute --project=${PROJECT} \
  networks create ${RDMA_NETWORK_PREFIX}-net \
  --network-profile=${ZONE}-vpc-roce \
  --subnet-mode=custom

# Create subnets for the HPC VPC in parallel
echo "Creating RDMA subnets..."
for N in $(seq 0 7); do
  gcloud compute --project=${PROJECT} \
    networks subnets create \
    ${RDMA_NETWORK_PREFIX}-sub-$N \
    --network=${RDMA_NETWORK_PREFIX}-net \
    --region=${REGION} \
    --range=192.168.$((N+1)).0/24 &
done

# Wait for all subnet creation background jobs to complete
wait
echo "✅ Network setup complete."


################################################################################
#                                                                              #
#                               CLUSTER SETUP                                  #
#                                                                              #
################################################################################

echo "🚀 Starting Cluster Setup..."

# Useful to check available GKE versions
# gcloud container get-server-config --format="yaml(validMasterVersions)" --zone=${ZONE} --project=${PROJECT}

# Create the GKE cluster
gcloud container clusters create ${CLUSTER_NAME} \
    --region=${REGION} \
    --cluster-version=${GKE_VERSION} \
    --workload-pool=${PROJECT}.svc.id.goog \
    --services-ipv4-cidr=10.65.0.0/19 \
    --cluster-ipv4-cidr=10.64.0.0/19 \
    --enable-dataplane-v2 \
    --enable-ip-alias \
    --enable-multi-networking \
    --no-enable-autoupgrade \
    --addons=GcsFuseCsiDriver \
    --machine-type="e2-standard-8" \
    --num-nodes=1 \
    --enable-autoscaling \
    --min-nodes=1 \
    --max-nodes=3

# Get credentials for the new cluster to configure kubectl
gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION} --project ${PROJECT}

# Apply network configurations from the YAML file
# NOTE: Ensure 'network.yaml' is correctly configured and present in the directory.
echo "Applying network_mapping.yaml..."
envsubst < network_mapping_template.yaml | kubectl apply -f -

echo "✅ Cluster setup complete."


################################################################################
#                                                                              #
#                              NODEPOOL CREATION                               #
#                                                                              #
################################################################################

echo "🚀 Starting Nodepool Creation..."

# Create the A3 UltraGPU node pool
gcloud container node-pools create ultra-nodepool-dws \
    --cluster=${CLUSTER_NAME} \
    --region=${REGION} \
    --node-locations=${ZONE} \
    --machine-type=a3-ultragpu-8g \
    --accelerator=type=nvidia-h200-141gb,count=8,gpu-driver-version=DEFAULT \
    --scopes="https://www.googleapis.com/auth/cloud-platform" \
    --reservation-affinity=none \
    --location-policy=ANY \
    --enable-queued-provisioning \
    --flex-start \
    --no-enable-autoupgrade \
    --no-enable-autorepair \
    --enable-autoscaling \
    --num-nodes=0 \
    --total-max-nodes=10 \
    --additional-node-network=network=${GVNIC_NETWORK_PREFIX}-net,subnetwork=${GVNIC_NETWORK_PREFIX}-sub \
    --additional-node-network=network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-0 \
    --additional-node-network=network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-1 \
    --additional-node-network=network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-2 \
    --additional-node-network=network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-3 \
    --additional-node-network=network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-4 \
    --additional-node-network=network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-5 \
    --additional-node-network=network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-6 \
    --additional-node-network=network=${RDMA_NETWORK_PREFIX}-net,subnetwork=${RDMA_NETWORK_PREFIX}-sub-7

echo "✅ Nodepool creation complete."


################################################################################
#                                                                              #
#                                 KUEUE SETUP                                  #
#                                                                              #
################################################################################

echo "🚀 Starting Kueue Setup..."

# Install Kueue job scheduler
kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/$KUEUE_VERSION/manifests.yaml

# Apply local Kueue configuration
# NOTE: Ensure 'kueue.yaml' is present in the directory.
echo "Applying kueue.yaml..."
kubectl apply -f kueue.yaml

echo "✅ Kueue setup complete."


################################################################################
#                                                                              #
#                                 NCCL SETUP                                   #
#                                                                              #
################################################################################

echo "🚀 Starting NCCL Setup..."

# Apply the NCCL RDMA installer
# NOTE: Ensure 'nccl_installer.yaml' is present in the directory.
echo "Applying nccl_installer.yaml..."
kubectl apply -f nccl_installer.yaml

# Check for the RDMA pods to confirm installation
echo "Verifying NCCL RDMA pods..."
kubectl get pod -n kube-system | grep rdma

echo "✅ NCCL setup complete."


################################################################################
#                                                                              #
#                           SERVICE PERMISSIONS SETUP                          #
#                                                                              #
################################################################################

echo "🚀 Starting Service Permissions Setup..."

# Create the Hugging Face secret in the cluster
kubectl create secret generic hf-secret \
--from-literal=hf_api_token=${HF_TOKEN}

# Create the GCS bucket for training data, models, etc.
gcloud storage buckets create gs://${GSBUCKET} --location=${REGION} --enable-hierarchical-namespace --uniform-bucket-level-access
gcloud storage buckets create gs://${GSDATABUCKET} --location=${REGION} --enable-hierarchical-namespace --uniform-bucket-level-access

# Create the Kubernetes Service Account (KSA) for GCS Fuse driver
kubectl create serviceaccount ${KSA_NAME} --namespace ${NAMESPACE}

# Grant the KSA permission to access the GCS bucket
gcloud storage buckets add-iam-policy-binding gs://${GSBUCKET} \
  --member "principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT}.svc.id.goog/subject/ns/${NAMESPACE}/sa/${KSA_NAME}" \
  --role "roles/storage.objectUser"

gcloud storage buckets add-iam-policy-binding gs://${GSDATABUCKET} \
  --member "principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT}.svc.id.goog/subject/ns/${NAMESPACE}/sa/${KSA_NAME}" \
  --role "roles/storage.objectUser"

echo "✅ Service permissions setup complete."
echo "🎉 All tasks finished successfully!"