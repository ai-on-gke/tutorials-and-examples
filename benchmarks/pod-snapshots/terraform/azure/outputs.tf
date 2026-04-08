output "cluster_name" {
  value=azurerm_kubernetes_cluster.cluster.name
}

output "resource_group_name" {
  value= data.azurerm_resource_group.rg.name
}

output "exporter_image" {
  value=module.common_info.images_to_build["exporter"].full_name
}

