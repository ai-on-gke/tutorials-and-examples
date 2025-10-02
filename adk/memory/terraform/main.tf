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

module "gke_cluster" {
  source            = "git::https://github.com/ai-on-gke/common-infra//common/infrastructure?ref=main"
  project_id        = var.project_id
  cluster_name      = var.cluster_name
  cluster_location  = var.cluster_location
  autopilot_cluster = var.autopilot_cluster
  private_cluster   = var.private_cluster
  create_network    = false
  network_name      = var.network_name
  subnetwork_name   = var.subnetwork_name
  subnetwork_region = var.subnetwork_region
  subnetwork_cidr   = var.subnetwork_cidr
  ray_addon_enabled = false
  depends_on        = [module.custom_network]
}

locals {
  cluster_membership_id = var.cluster_membership_id == "" ? var.cluster_name : var.cluster_membership_id
  host                  = var.private_cluster ? "https://connectgateway.googleapis.com/v1/projects/${data.google_project.project.number}/locations/${var.cluster_location}/gkeMemberships/${local.cluster_membership_id}" : "https://${module.gke_cluster.endpoint}"

}

provider "kubernetes" {
  alias                  = "cluster"
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

resource "google_artifact_registry_repository" "image_repo" {
  project       = var.project_id
  location      = var.image_repository_location
  repository_id = var.image_repository_name
  format        = "DOCKER"
}

resource "google_artifact_registry_repository_iam_binding" "registry_binding_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.image_repo.location
  repository = google_artifact_registry_repository.image_repo.repository_id
  role       = "roles/artifactregistry.reader"
  members = [
    "serviceAccount:${module.gke_cluster.service_account}",
  ]
  depends_on = [google_artifact_registry_repository.image_repo, module.gke_cluster]
}

locals {
  image_repository_full_name = "${var.image_repository_location}-docker.pkg.dev/${var.project_id}/${var.image_repository_name}"
}

resource "local_file" "agent_manifest" {
  content = templatefile(
    "${path.module}/templates/agent-with-memory.yaml.tftpl",
    {
      IMAGE_NAME      = local.image_repository_full_name
      SESSION_DB_HOST = module.cloudsql.instance_ip_address[0].ip_address
      SESSION_DB_NAME = var.cloudsql_adk_database_name
      SESSION_DB_USER = var.cloudsql_database_user
      VECTOR_DB_HOST  = module.cloudsql.instance_ip_address[0].ip_address
      VECTOR_DB_NAME  = var.cloudsql_agent_memory_database_name
      VECTOR_DB_USER  = var.cloudsql_database_user
    }
  )
  filename = "${path.module}/../gen/agent-with-memory.yaml"
}
