output "cluster_name" {
  value=aws_eks_cluster.cluster.name
}

output "cluster_region" {
  value=aws_eks_cluster.cluster.region
}

output "exporter_image" {
  value=module.common_info.images_to_build["exporter"].full_name
}

