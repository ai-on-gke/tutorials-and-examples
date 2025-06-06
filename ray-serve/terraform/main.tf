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

data "google_client_config" "default" {}

data "google_project" "project" {
  project_id = var.project_id
}
locals {
  cluster_name = var.cluster_name != "" ? var.cluster_name : var.default_resource_name
}

# Enable Cloud Resource Manager API
resource "google_project_service" "cloudresourcemanager" {
  project = var.project_id
  service = "cloudresourcemanager.googleapis.com"

  # Prevent disabling the API if it's already enabled
  disable_on_destroy = false
}

module "gke_cluster" {
  source            = "github.com/ai-on-gke/common-infra//common/infrastructure?ref=main"
  project_id        = var.project_id
  cluster_name      = local.cluster_name
  cluster_location  = var.cluster_location
  autopilot_cluster = var.autopilot_cluster
  private_cluster   = var.private_cluster
  create_network    = false
  network_name      = local.network_name
  subnetwork_name   = local.subnetwork_name
  subnetwork_region = var.subnetwork_region
  subnetwork_cidr   = var.subnetwork_cidr
  ray_addon_enabled = false
  depends_on        = [module.custom_network]
}

resource "google_storage_bucket_iam_member" "cloudbuild_storage_viewer" {
  bucket = "${var.project_id}_cloudbuild"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

resource "google_artifact_registry_repository_iam_member" "cloudbuild_artifact_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.image_repo.location
  repository = google_artifact_registry_repository.image_repo.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

locals {
  cluster_membership_id = var.cluster_membership_id == "" ? local.cluster_name : var.cluster_membership_id
  host                  = var.private_cluster ? "https://connectgateway.googleapis.com/v1/projects/${data.google_project.project.number}/locations/${var.cluster_location}/gkeMemberships/${local.cluster_membership_id}" : "https://${module.gke_cluster.endpoint}"

}

provider "kubernetes" {
  alias                  = "adk"
  host                   = local.host
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = var.private_cluster ? "" : base64decode(module.gke_cluster.ca_certificate)

  dynamic "exec" {
    for_each = var.private_cluster ? [1] : []
    content {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}
