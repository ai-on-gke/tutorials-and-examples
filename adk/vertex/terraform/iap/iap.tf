# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

data "terraform_remote_state" "infra" {
  backend = "local"

  config = {
    path = "../infra/terraform.tfstate"
  }
}

data "google_client_config" "default" {}


data "google_container_cluster" "cluster" {
  project =  data.terraform_remote_state.infra.outputs.project_id
  name =  data.terraform_remote_state.infra.outputs.gke_cluster_name
  location = data.terraform_remote_state.infra.outputs.gke_cluster_location
}

provider "kubernetes" {
  alias                  = "adk"
  host                   = data.terraform_remote_state.infra.outputs.cluster_host
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = data.terraform_remote_state.infra.outputs.cluster_ca_certificate

}

provider "helm" {
  alias                  = "adk"
  kubernetes {
    host                   = data.terraform_remote_state.infra.outputs.cluster_host
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = data.terraform_remote_state.infra.outputs.cluster_ca_certificate
  }
}


module "iap_auth" {
  source = "github.com/ai-on-gke/common-infra//common/modules/iap?ref=main"

  providers = {
    kubernetes = kubernetes.adk
    helm = helm.adk
  }

  project_id =  data.terraform_remote_state.infra.outputs.project_id
  namespace                = var.kubernetes_namespace
  support_email            = var.support_email
  app_name                 = var.app_name
  create_brand             = var.create_brand
  k8s_ingress_name         = var.k8s_ingress_name
  k8s_managed_cert_name    = var.k8s_managed_cert_name
  k8s_iap_secret_name      = var.k8s_iap_secret_name
  k8s_backend_config_name  = var.k8s_backend_config_name
  k8s_backend_service_name = var.k8s_app_service_name
  k8s_backend_service_port = var.k8s_app_service_port
  client_id                = var.oauth_client_id
  client_secret            = var.oauth_client_secret
  domain                   = var.domain
  members_allowlist        = var.members_allowlist
}


