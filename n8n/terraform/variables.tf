variable "project_id" {
  type = string
}
variable "default_resource_name" {
  type = string
}
variable "cluster_name" {
  type = string
}
variable "cluster_location" {
  type = string
}
variable "autopilot_cluster" {
  type = bool
}
variable "private_cluster" {
  type = bool
}
variable "cluster_membership_id" {
  type        = string
  description = "require to use connectgateway for private clusters, default: cluster_name"
  default     = ""
}
variable "network_name" {
  type = string
}
variable "subnetwork_name" {
  type = string
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
  default = "This is a subnetwork for a GKE tutorial"
}

variable "cloudsql_instance_name" {
  type    = string
  default = ""
}

variable "cloudsql_instance_region" {
  type        = string
  description = "GCP region for CloudSQL instance"
}

variable "cloudsql_db_name" {
  type        = string
  description = "Cloud SQL database name"
  default     = "n8n"
}

variable "cloudsql_db_user" {
  type        = string
  description = "Cloud SQL instance user"
  default     = "n8n"
}

variable "ollama_service_account_name" {
  type = string
}
variable "ollama_bucket_name" {
  type = string
}
