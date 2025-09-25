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

variable "project_id" {
  type = string
}

variable "cluster_name" {
  type    = string
  default = "adk-agent-memory-tutorial-tf"
}

variable "cluster_location" {
  type = string
}

variable "autopilot_cluster" {
  type    = bool
  default = true
}
variable "private_cluster" {
  type    = bool
  default = false
}
variable "cluster_membership_id" {
  type        = string
  description = "require to use connectgateway for private clusters, default: cluster_name"
  default     = ""
}
variable "network_name" {
  type    = string
  default = "adk-agent-memory-tutorial-tf"
}
variable "subnetwork_name" {
  type    = string
  default = "adk-agent-memory-tutorial-tf"
}
variable "subnetwork_cidr" {
  type = string
}

variable "subnetwork_region" {
  type = string
}

variable "subnetwork_private_access" {
  type    = string
  default = "true"
}

variable "subnetwork_description" {
  type    = string
  default = ""
}

variable "kubernetes_namespace" {
  type    = string
  default = "default"
}

variable "image_repository_name" {
  type        = string
  description = "Name of Artifact Registry Repository"
  default     = "adk-agent-memory-tutorial-tf"
}

variable "image_repository_location" {
  type        = string
  description = "Location of Artifact Registry Repository"
  default     = "us-central1"
}

variable "cloudsql_instance_name" {
  type    = string
  default = "adk-agent-memory-tutorial-tf"
}

variable "cloudsql_instance_region" {
  type    = string
  default = "us-central1"
}

variable "cloudsql_adk_database_name" {
  type    = string
  default = "adk"
}

variable "cloudsql_agent_memory_database_name" {
  type    = string
  default = "agent-memory"
}
variable "cloudsql_database_user" {
  type    = string
  default = "postgres"
}

