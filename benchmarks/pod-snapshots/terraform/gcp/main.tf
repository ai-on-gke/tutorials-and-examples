provider "google" {
  project = var.project_id
}

data "google_project" "current" {
  project_id = var.project_id
}

data "google_client_config" "default" {}

locals {
  #registry_uri = "${google_artifact_registry_repository.repository.location}-docker.pkg.dev/${google_artifact_registry_repository.repository.project}"
  registry_uri = "${google_artifact_registry_repository.repository.location}-docker.pkg.dev" 
  registry_username = "oauth2accesstoken"
  registry_password = data.google_client_config.default.access_token
}
module "common_info" {
  source = "../modules/common_info"
  
  image_name_prefix = "${var.name_prefix}"
  registry_uri = "${local.registry_uri}/${google_artifact_registry_repository.repository.project}"
  public_images_to_pull = var.public_images_to_pull
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.cluster.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = "https://${google_container_cluster.cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.cluster.master_auth[0].cluster_ca_certificate)
  }
}

provider "docker" {
  host  = "unix:///var/run/docker.sock"
  registry_auth {
    address  = local.registry_uri
    username = local.registry_username
    password = local.registry_password
  }
}

module "benchmarking_infra" {
  source = "../modules/benchmarking_infra"

  name_prefix = "${var.name_prefix}-gcp"
  cloud_provider = "gcp"
  images_to_build = module.common_info.images_to_build
  #registry_uri = "${google_artifact_registry_repository.repository.location}-docker.pkg.dev"
  #registry_username = "oauth2accesstoken"
  #registry_password = data.google_client_config.default.access_token
  model_storage_bucket_name = google_storage_bucket.model_storage_bucket.name
  k3s_service_accounts = module.common_info.k3s_service_accounts
  registry_extra_info = {
    service_account_annotations={
      "iam.gke.io/gcp-service-account"=google_service_account.registry_pod_workload_sa.email
    },
  }
  model_storage_extra_info = {
    service_account_annotations={
      "iam.gke.io/gcp-service-account"=google_service_account.model_storage_workload_sa.email
    },
  }
  pod_snapshot_extra_info = {
    bucket_name = google_storage_bucket.pod_snapshot_storage_bucket.name
    service_account_annotations={
      "iam.gke.io/gcp-service-account"=google_service_account.pod_snapshot_storage_workload_sa.email
    },
  }
  hf_token = var.hf_token
  models_to_download = var.models_to_download
  model_used_in_test=var.model_used_in_test
  image_used_in_test=var.image_used_in_test
  public_images_to_pull = module.common_info.public_images_to_pull


  depends_on = [
    terraform_data.ready_cluster,
  ]

}

