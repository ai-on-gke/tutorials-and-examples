# # Copyright 2025 Google LLC
# #
# # Licensed under the Apache License, Version 2.0 (the "License");
# # you may not use this file except in compliance with the License.
# # You may obtain a copy of the License at
# #
# #     http://www.apache.org/licenses/LICENSE-2.0
# #
# # Unless required by applicable law or agreed to in writing, software
# # distributed under the License is distributed on an "AS IS" BASIS,
# # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# # See the License for the specific language governing permissions and
# # limitations under the License.

variable "project_id" {
  type        = string
  description = "GCP project id"
}

variable "project_number" {
  type        = number
  description = "GCP project number"
}

variable "cluster_name" {
  type = string
}

variable "cluster_location" {
  type = string
}

variable "cluster_membership_id" {
  type        = string
  description = "require to use connectgateway for private clusters, default: cluster_name"
  default     = ""
}

variable "kubernetes_namespace" {
  type        = string
  description = "Kubernetes namespace where resources are deployed"
  default     = "ai-on-gke"
}

variable "create_gcs_bucket" {
  type        = bool
  default     = false
  description = "Enable flag to create gcs_bucket"
}

variable "gcs_bucket" {
  type        = string
  description = "The GCS bucket to store data for the Ray cluster."
}

variable "image_repository_name" {
  type = string
  default = "gemma"
}

variable "image_repository_location" {
  type    = string
  default = "us"
}

variable "create_service_account" {
  type        = bool
  description = "Creates a google IAM service account & k8s service account & configures workload identity"
  default     = true
}

variable "workload_identity_service_account" {
  type        = string
  description = "Google Cloud IAM service account for authenticating with GCP services for GCS"
  default     = "ray-sa"
}

variable "enable_gpu" {
  type    = bool
  default = false
}

variable "enable_tpu" {
  type    = bool
  default = false
}

## GKE variables
variable "create_cluster" {
  type    = bool
  default = false
}

variable "private_cluster" {
  type    = bool
  default = false
}

variable "autopilot_cluster" {
  type    = bool
  default = true
}

variable "cpu_pools" {
  type = list(object({
    name                   = string
    machine_type           = string
    node_locations         = optional(string, "")
    autoscaling            = optional(bool, false)
    min_count              = optional(number, 1)
    max_count              = optional(number, 3)
    local_ssd_count        = optional(number, 0)
    spot                   = optional(bool, false)
    disk_size_gb           = optional(number, 100)
    disk_type              = optional(string, "pd-standard")
    image_type             = optional(string, "COS_CONTAINERD")
    enable_gcfs            = optional(bool, false)
    enable_gvnic           = optional(bool, false)
    logging_variant        = optional(string, "DEFAULT")
    auto_repair            = optional(bool, true)
    auto_upgrade           = optional(bool, true)
    create_service_account = optional(bool, true)
    preemptible            = optional(bool, false)
    initial_node_count     = optional(number, 1)
    accelerator_count      = optional(number, 0)
  }))
  default = [{
    name         = "cpu-pool"
    machine_type = "n1-standard-16"
    autoscaling  = true
    min_count    = 1
    max_count    = 3
    enable_gcfs  = true
    disk_size_gb = 100
    disk_type    = "pd-standard"
  }]
}

variable "gpu_pools" {
  type = list(object({
    name                   = string
    machine_type           = string
    node_locations         = optional(string, "")
    autoscaling            = optional(bool, false)
    min_count              = optional(number, 1)
    max_count              = optional(number, 3)
    local_ssd_count        = optional(number, 0)
    spot                   = optional(bool, false)
    disk_size_gb           = optional(number, 100)
    disk_type              = optional(string, "pd-standard")
    image_type             = optional(string, "COS_CONTAINERD")
    enable_gcfs            = optional(bool, false)
    enable_gvnic           = optional(bool, false)
    logging_variant        = optional(string, "DEFAULT")
    auto_repair            = optional(bool, true)
    auto_upgrade           = optional(bool, true)
    create_service_account = optional(bool, true)
    preemptible            = optional(bool, false)
    initial_node_count     = optional(number, 1)
    accelerator_count      = optional(number, 0)
    accelerator_type       = optional(string, "nvidia-tesla-t4")
    gpu_driver_version     = optional(string, "DEFAULT")
    queued_provisioning    = optional(bool, false)
  }))
  default = [{
    name               = "gpu-pool-l4"
    machine_type       = "g2-standard-24"
    autoscaling        = true
    min_count          = 0
    max_count          = 3
    disk_size_gb       = 100
    disk_type          = "pd-balanced"
    enable_gcfs        = true
    accelerator_count  = 2
    accelerator_type   = "nvidia-l4"
    gpu_driver_version = "DEFAULT"
  }]
}

variable "goog_cm_deployment_name" {
  type    = string
  default = ""
}

# These default resource quotas are set intentionally high as an example that won't be limiting for most Ray clusters.
# Consult https://kubernetes.io/docs/concepts/policy/resource-quotas/ for additional quotas that may be set.
variable "resource_quotas" {
  description = "Kubernetes ResourceQuota object to attach to the Ray cluster's namespace"
  type        = map(string)
  default = {
    cpu                       = "1000"
    memory                    = "10Ti"
    "requests.nvidia.com/gpu" = "100"
    "requests.google.com/tpu" = "100"
  }
}

variable "disable_resource_quotas" {
  description = "Set to true to remove resource quotas from your Ray clusters. Not recommended"
  type        = bool
  default     = false
}

# This is a list of CIDR ranges allowed to access a Ray cluster's job submission API and Dashboard.
#
# Example:
# kuberay_network_policy_allow_cidr = "10.0.0.0/8"
#
variable "kuberay_network_policy_allow_cidr" {
  description = "List of CIDRs that are allowed to access this Ray cluster's job submission and dashboard port."
  type        = string
  default     = ""
}

variable "disable_ray_cluster_network_policy" {
  description = "Disables Kubernetes Network Policy for Ray Clusters for this demo. Defaulting to 'true' aka disabled pending fixes to the kuberay-monitoring module. This should be defaulted to false."
  type        = bool
  default     = false
}

variable "additional_labels" {
  // string is used instead of map(string) since blueprint metadata does not support maps.
  type        = string
  description = "Additional labels to add to Kubernetes resources."
  default     = "created-by=ai-on-gke,ai.gke.io=ray"
}
