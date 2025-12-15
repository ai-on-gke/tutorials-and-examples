/**
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


# Review and update this file with variable values before provisioning infrastructure.

project_id      = "<YOUR_PROJECT_ID>"
location        = "<CLUSTER_LOCATION>"
runner_zone     = "<LINKED_RUNNER_ZONE>"
cluster_name    = "<CLUSTER_NAME>"
cluster_version = "<CLUSTER_VERSION>"       # 1.34.1-gke.2811000 or later

# Linked runner setup
runner_sa              = "<RUNNER_SA>"                # e.g. "linked-runner-sa"
cgke_image_name        = "<IMAGE_NAME>"               # e.g. "cos-confidential-gke-251101"
cgke_image_project     = "<IMAGE_PROJECT>"            # e.g. "confidential-gke-images"
tee_policy             = "<TEE_POLICY_STRING>"        # Fill in encoded policy
reservation_project_id = "<RESERVATION_PROJECT_ID>"   # Fill in for TPU reservation
reservation_name       = "<RESERVATION_NAME>"         # Fill in for TPU reservation

# [OPTIONAL] Additional node network
# If you don't need the resources in network.tf, remove below and also from variables.tf
network_name           = "<NETWORK_NAME>"
subnetwork_name        = "<SUBNETWORK_NAME>"
subnetwork_region      = "<SUBNETWORK_REGION>"        # Usually matches cluster region
