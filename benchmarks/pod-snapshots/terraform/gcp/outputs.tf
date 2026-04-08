output "cluster_name" {
  value=google_container_cluster.cluster.name
}

output "cluster_location" {
  value=google_container_cluster.cluster.location
}

output "exporter_image" {
  value=module.common_info.images_to_build["exporter"].full_name
}

