resource "azurerm_kubernetes_cluster" "cluster" {
  name                = local.cluster_name
  location = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  dns_prefix          = "exampleaks1"

  default_node_pool {
    name       = "system"
    node_count = 1
    vm_size    = "Standard_D8ds_v5"
    vnet_subnet_id = azurerm_subnet.subnet.id
    temporary_name_for_rotation = "defaulttemp"
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "node_pool" {
  for_each = var.node_pools
  name                  = replace(each.key, "-", "")
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cluster.id
  
  vnet_subnet_id = azurerm_subnet.subnet.id
  
  vm_size = each.value.machine_type
  os_sku =  each.value.os_sku
  auto_scaling_enabled = true
  min_count = each.value.min_count
  max_count = each.value.max_count
  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
  }
  gpu_driver = "None"
  node_taints = concat(
    [],
    each.value.gpu_enabled? ["sku=gpu:NoSchedule"]: []
  )
  
  workload_runtime=each.value.workload_runtime 


}

