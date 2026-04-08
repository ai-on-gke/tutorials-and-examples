resource "azurerm_container_registry" "registry" {
  name                = var.name_prefix
  resource_group_name = data.azurerm_resource_group.rg.name
  location = var.location
  sku                 = "Standard" 
  admin_enabled       = true 
}


resource "azurerm_role_assignment" "cluster_acr_role" {
  scope                            = azurerm_container_registry.registry.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.cluster.kubelet_identity[0].object_id
}

resource "azurerm_user_assigned_identity" "acr_workload_identity" {
  name                = "${var.name_prefix}-acr-wid"
  resource_group_name = data.azurerm_resource_group.rg.name
  location = var.location
}


resource "azurerm_role_assignment" "acr_workload_identity_role" {
  scope                = azurerm_container_registry.registry.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.acr_workload_identity.principal_id
}


resource "azurerm_federated_identity_credential" "acr_workload_id_credential" {
  for_each = { for sa in ["image-registry-helpers"]: sa=>module.common_info.k3s_service_accounts[sa] }
  name                = "${var.name_prefix}-acr-fic"
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.acr_workload_identity.id
  subject             = "system:serviceaccount:${each.value.namespace}:${each.value.name}"
  depends_on = [
    azurerm_role_assignment.acr_workload_identity_role,
  ]
}
