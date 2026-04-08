provider "google" {
  project = var.project_id
}

data "google_client_config" "default" {}

locals {
  cluster_name = var.default_name
  cluster_host = "https://${google_container_cluster.cluster.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.cluster.master_auth.0.cluster_ca_certificate)
}


provider "kubernetes" {
  host                   = local.cluster_host
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = local.cluster_ca_certificate
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_host
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = local.cluster_ca_certificate
  }
}
