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
# We disable it for the cleanup script to ensure it tries to delete all resources,
# even if one has already been removed.
# set -e

# Load the environment variables from the .env file
source .env

################################################################################
#                                                                              #
#                                 SAFETY CHECK                                 #
#                                                                              #
################################################################################

echo "🚨 WARNING: This script is DESTRUCTIVE and will delete ALL resources"
echo "   associated with the cluster '${CLUSTER_NAME}' in project '${PROJECT}'."
echo ""
echo "   This includes:"
echo "   - GKE Cluster: ${CLUSTER_NAME} and its node pools"
echo "   - GCS Bucket: gs://${GSBUCKET}"
echo "   - GCS Bucket: gs://${GSDATABUCKET}"
echo "   - VPCs: ${GVNIC_NETWORK_PREFIX}-net and ${RDMA_NETWORK_PREFIX}-net"
echo "   - All associated subnets and firewall rules"
echo ""
read -p "Are you absolutely sure you want to proceed? Type 'yes' to confirm: " confirmation
if [[ "$confirmation" != "yes" ]]; then
    echo "Cleanup cancelled by user."
    exit 1
fi
echo ""
echo "✅ Confirmation received. Starting cleanup..."


################################################################################
#                                                                              #
#                           GKE & K8S RESOURCE CLEANUP                         #
#                                                                              #
################################################################################

echo "🚀 Deleting GKE Node Pool..."
gcloud container node-pools delete ultra-nodepool-dws \
    --cluster=${CLUSTER_NAME} \
    --region=${REGION} \
    --quiet || echo "Node pool 'ultra-nodepool-dws' not found or already deleted."

echo "🚀 Deleting GKE Cluster..."
gcloud container clusters delete ${CLUSTER_NAME} \
    --region=${REGION} \
    --quiet || echo "Cluster '${CLUSTER_NAME}' not found or already deleted."


################################################################################
#                                                                              #
#                             GCS BUCKET CLEANUP                               #
#                                                                              #
################################################################################

echo "🚀 Deleting GCS Bucket..."
# The IAM policy binding is deleted automatically with the bucket.
gcloud storage buckets delete gs://${GSBUCKET} \
    --quiet || echo "Bucket 'gs://${GSBUCKET}' not found or already deleted."

gcloud storage buckets delete gs://${GSDATABUCKET} \
    --quiet || echo "Bucket 'gs://${GSDATABUCKET}' not found or already deleted."


################################################################################
#                                                                              #
#                              NETWORK CLEANUP                                 #
#                                                                              #
################################################################################

echo "🚀 Deleting gVNIC Network Resources..."
gcloud compute firewall-rules delete ${GVNIC_NETWORK_PREFIX}-internal \
    --quiet || echo "Firewall rule '${GVNIC_NETWORK_PREFIX}-internal' not found."

gcloud compute networks subnets delete ${GVNIC_NETWORK_PREFIX}-sub \
    --region=${REGION} \
    --quiet || echo "Subnet '${GVNIC_NETWORK_PREFIX}-sub' not found."

gcloud compute networks delete ${GVNIC_NETWORK_PREFIX}-net \
    --quiet || echo "VPC '${GVNIC_NETWORK_PREFIX}-net' not found."


echo "🚀 Deleting RDMA Network Resources..."
# Delete RDMA subnets in parallel
for N in $(seq 0 7); do
  gcloud compute networks subnets delete ${RDMA_NETWORK_PREFIX}-sub-$N \
    --region=${REGION} \
    --quiet &
done

# Wait for all subnet deletion jobs to complete
wait
echo "All RDMA subnet deletion commands issued."

gcloud compute networks delete ${RDMA_NETWORK_PREFIX}-net \
    --quiet || echo "VPC '${RDMA_NETWORK_PREFIX}-net' not found."

echo "✅ Network cleanup complete."
echo "🎉 All cleanup tasks finished!"