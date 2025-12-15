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

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "location" {
  description = "Cluster location"
  type        = string
}

variable "runner_zone" {
  description = "Linked runner zone"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to use for the GKE cluster"
  type        = string
  default     = "1.34.1-gke.2811000"
}

variable "runner_sa" {
  description = "Service account to use for the runner node pool"
  type        = string
}

variable "cgke_image_name" {
  description = "Linked runner COS image name"
  type        = string
  default     = "cos-confidential-gke-251101"
}

variable "cgke_image_project" {
  description = "Linked runner COS image project"
  type        = string
  default     = "confidential-gke-images"
}

variable "tee_policy" {
  description = "Encoded TEE policy to use for the linked runner node pool"
  type        = string
  default     = ""
}

# For TPU reservation 
# https://docs.cloud.google.com/compute/docs/instances/reservations-consume#consuming_instances_from_a_specific_reservation
variable "reservation_project_id" {
  description = "Reservation owner project ID"
  type        = string
}

variable "reservation_name" {
  description = "Name of the reservation"
  type        = string
}

# [OPTIONAL] Additional node network variables used in network.tf
# Clean up the below variables if network.tf is removed
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnetwork_name" {
  description = "Name of the VPC subnetwork"
  type        = string
}

variable "subnetwork_region" {
  description = "Region of the VPC subnetwork"
  type        = string
}
