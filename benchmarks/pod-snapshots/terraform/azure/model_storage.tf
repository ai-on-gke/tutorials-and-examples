resource "azurerm_storage_account" "storage_account" {
  name                     =  var.name_prefix
  resource_group_name = data.azurerm_resource_group.rg.name
  location =                  var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  network_rules {
    default_action             = "Deny" # Blocks all public internet access
    virtual_network_subnet_ids = [azurerm_subnet.subnet.id] # Allows AKS
  }
}

resource "azurerm_storage_container" "storage_container" {
  name                  = var.name_prefix
  storage_account_id    = azurerm_storage_account.storage_account.id
  container_access_type = "private"
}

resource "azurerm_user_assigned_identity" "model_storage_container_identity" {
  name                = "${var.name_prefix}-model-storage-identity"
  resource_group_name = data.azurerm_resource_group.rg.name
  location =                  var.location
}

resource "azurerm_role_assignment" "storage_access" {
  scope                = azurerm_storage_account.storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.model_storage_container_identity.principal_id
}

resource "azurerm_federated_identity_credential" "model_downloader_federated_auth" {
  for_each = { for sa in ["model-storage-helpers", "runai_vllm_test"]: sa=>module.common_info.k3s_service_accounts[sa] }
  name                = "${var.name_prefix}-${each.key}-model-deownloader-fic"
  parent_id           = azurerm_user_assigned_identity.model_storage_container_identity.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster.oidc_issuer_url
  subject             = "system:serviceaccount:${each.value.namespace}:${each.value.name}"
}
#resource "azurerm_federated_identity_credential" "runai_streamer_federated_auth" {
#  name                = "${var.name_prefix}-runai-streamer-fic"
#  parent_id           = azurerm_user_assigned_identity.model_storage_container_identity.id
#  audience            = ["api://AzureADTokenExchange"]
#  issuer              = module.cluster.azure_cluster_oidc_issuer_url
#  subject             = "system:serviceaccount:default:runai-streamer-sa"
#}
