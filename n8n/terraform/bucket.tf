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
  ollama_bucket_name          = var.ollama_bucket_name != "" ? var.ollama_bucket_name : var.default_resource_name
  ollama_service_account_name = var.ollama_service_account_name != "" ? var.ollama_service_account_name : var.default_resource_name
}


resource "google_storage_bucket" "bucket" {
  project = var.project_id
  name    = local.ollama_bucket_name

  location      = "US"
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
  force_destroy               = true
}

module "workload_identity" {
  providers = {
    kubernetes = kubernetes.n8n
  }
  source     = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  name       = local.ollama_service_account_name
  namespace  = "default"
  roles      = ["roles/storage.objectUser"]
  project_id = var.project_id
  depends_on = [module.gke_cluster]
}
