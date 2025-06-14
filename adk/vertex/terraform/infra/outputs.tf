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

output "project_id" {
  value = var.project_id
}
output "gke_cluster_name" {
  value       = local.cluster_name
  description = "GKE cluster name"
}

output "gke_cluster_location" {
  value       = var.cluster_location
  description = "GKE cluster location"
}

output "private_cluster" {
  value = var.private_cluster
}

output "cluster_membership_id" {
  value = local.cluster_membership_id
}

output "cluster_host" {
  value = local.host
}

output "cluster_ca_certificate" {
  value = local.cluster_ca_certificate
  sensitive = true
}

output "image_repository_name" {
  value = local.image_repository_name
}
output "image_repository_location" {
  value = var.image_repository_location
}


output "image_repository_full_name" {
  value = "${var.image_repository_location}-docker.pkg.dev/${var.project_id}/${local.image_repository_name}"
}

output "k8s_service_account_name" {
  value = local.k8s_service_account_name
}

