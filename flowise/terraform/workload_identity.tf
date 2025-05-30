# Copyright 2025 Google LLC
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

locals {
  iam_service_account_name = var.iam_service_account_name != "" ? var.iam_service_account_name : var.default_resource_name
  k8s_service_account_name = var.k8s_service_account_name != "" ? var.k8s_service_account_name : var.default_resource_name
}


module "workload_identity" {
  providers = {
    kubernetes = kubernetes.flowise
  }
  source      = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  name        = local.iam_service_account_name
  k8s_sa_name = local.k8s_service_account_name
  namespace   = var.kubernetes_namespace
  roles = [
    "roles/storage.objectUser",
    "roles/aiplatform.user"
  ]
  automount_service_account_token = true
  project_id                      = var.project_id
  depends_on                      = [module.gke_cluster]
}
