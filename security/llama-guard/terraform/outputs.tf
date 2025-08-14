output "project_id" {
  value = var.project_id
}
output "gke_cluster_name" {
  value       = var.cluster_name
}

output "gke_cluster_location" {
  value       = var.cluster_location
}

output "image_repository_name" {
  value = var.image_repository_name
}
output "image_repository_location" {
  value = var.image_repository_location
}


output "image_repository_full_name" {
  value = local.image_repository_full_name
}
