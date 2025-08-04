data "google_client_config" "default" {}

data "google_project" "project" {
  project_id = var.project_id
}

data "google_container_cluster" "cluster" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.cluster_location
}

locals {
  private_cluster        = data.google_container_cluster.cluster.private_cluster_config[0].enable_private_endpoint
  cluster_membership_id  = local.private_cluster ? data.google_container_cluster.cluster.fleet[0].membership_id : ""
  host                   = local.private_cluster ? "https://connectgateway.googleapis.com/v1/projects/${data.google_project.project.number}/locations/${var.cluster_location}/gkeMemberships/${local.cluster_membership_id}" : "https://${data.google_container_cluster.cluster.endpoint}"
  cluster_ca_certificate = base64decode(data.google_container_cluster.cluster.master_auth[0].cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "cluster"
  host                   = local.host
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = local.private_cluster ? "" : local.cluster_ca_certificate
  dynamic "exec" {
    for_each = local.private_cluster == true ? [1] : []
    content {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}

provider "helm" {
  alias = "cluster"
  kubernetes = {
    host                   = local.host
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = local.private_cluster ? "" : local.cluster_ca_certificate
    exec = local.private_cluster == true ? {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    } : null
  }
}
