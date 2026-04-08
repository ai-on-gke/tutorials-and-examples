provider "azurerm" {
  subscription_id=var.subscription_id
  resource_provider_registrations = "none"
  features {}
}

data "azurerm_subscription" "current" {}

data "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
}

locals {
  cluster_name = var.default_name
  cluster_host          = azurerm_kubernetes_cluster.cluster.kube_config[0].host
  cluster_client_certificate = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_certificate)
  cluster_client_key = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate)
  cluster_username = azurerm_kubernetes_cluster.cluster.kube_config[0].username
  cluster_password = azurerm_kubernetes_cluster.cluster.kube_config[0].password

}

provider "kubernetes" {
  host                   = local.cluster_host
  cluster_ca_certificate = local.cluster_ca_certificate
  client_certificate = local.cluster_client_certificate
  client_key = local.cluster_client_key
  username = local.cluster_username
  password = local.cluster_password
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_host
    cluster_ca_certificate = local.cluster_ca_certificate
    client_certificate = local.cluster_client_certificate
    client_key = local.cluster_client_key
    username = local.cluster_username
    password = local.cluster_password
  }
}

