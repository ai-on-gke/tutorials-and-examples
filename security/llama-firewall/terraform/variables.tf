variable "project_id" {
  type = string
}

variable "cluster_name" {
  type = string
  default = "llama-firewall-tutorial-tf"
}

variable "cluster_location" {
  type = string
}

variable "autopilot_cluster" {
  type = bool
  default = true
}
variable "private_cluster" {
  type = bool
  default = false
}
variable "cluster_membership_id" {
  type        = string
  description = "require to use connectgateway for private clusters, default: cluster_name"
  default     = ""
}
variable "network_name" {
  type = string
  default = "llama-firewall-tutorial-tf"
}
variable "subnetwork_name" {
  type = string
  default = "llama-firewall-tutorial-tf"
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
  type = string
  description = "Name of Artifact Registry Repository"
  default = "llama-firewall-tutorial-tf"
}

variable "image_repository_location" {
  type = string
  description = "Location of Artifact Registry Repository"
  default = "us-central1"
}
