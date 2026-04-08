provider "azurerm" {
  subscription_id=var.subscription_id
  resource_provider_registrations = "none"
  features {}
}

data "azurerm_subscription" "current" {}

data "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.cluster.kube_config[0].host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate)
  client_certificate = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_certificate)
  client_key = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_key)
  username = azurerm_kubernetes_cluster.cluster.kube_config[0].username
  password = azurerm_kubernetes_cluster.cluster.kube_config[0].password
}

provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.cluster.kube_config[0].host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate)
    client_certificate = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_certificate)
    client_key = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_key)
    username = azurerm_kubernetes_cluster.cluster.kube_config[0].username
    password = azurerm_kubernetes_cluster.cluster.kube_config[0].password
  }
}
  

locals {
  registry_uri = azurerm_container_registry.registry.login_server
  registry_username = azurerm_container_registry.registry.admin_username
  registry_password = azurerm_container_registry.registry.admin_password
  common_workload_identity_pod_labels = {
    "azure.workload.identity/use" = "true"
  }
}

module "common_info" {
  source = "../modules/common_info"
  image_name_prefix = var.name_prefix
  registry_uri = local.registry_uri
  public_images_to_pull = var.public_images_to_pull
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

  name_prefix = "${var.name_prefix}-azure"
  cloud_provider = "azure"
  images_to_build = module.common_info.images_to_build
  k3s_service_accounts = module.common_info.k3s_service_accounts
  registry_extra_info = {
    service_account_annotations={
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.acr_workload_identity.client_id
    },
    pod_labels = local.common_workload_identity_pod_labels,
    pod_environment_variables = {
      "AZURE_ACR_REGISTRY_NAME" = azurerm_container_registry.registry.name
    }
  }
  model_storage_bucket_name = azurerm_storage_container.storage_container.name
  model_storage_extra_info = {
    service_account_annotations={
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.model_storage_container_identity.client_id
    }
    pod_labels = local.common_workload_identity_pod_labels 
    pod_environment_variables = {
      "AZURE_STORAGE_ACCOUNT_NAME" = azurerm_storage_account.storage_account.name
    }
  }
  hf_token = var.hf_token
  models_to_download = var.models_to_download
  model_used_in_test=var.model_used_in_test
  image_used_in_test=var.image_used_in_test
  public_images_to_pull = module.common_info.public_images_to_pull

  depends_on = [
    kubernetes_daemon_set_v1.nvidia_device_plugin,
  ]

}

