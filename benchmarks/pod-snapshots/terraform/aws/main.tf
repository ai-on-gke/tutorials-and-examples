provider "aws" {
  region = var.region
}

data "aws_ecr_authorization_token" "token" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  registry_uri = format("%v.dkr.ecr.%v.amazonaws.com", data.aws_caller_identity.current.account_id, data.aws_region.current.region)
  registry_username = data.aws_ecr_authorization_token.token.user_name
  registry_password = data.aws_ecr_authorization_token.token.password
}


module "common_info" {
  source = "../modules/common_info"
  
  image_name_prefix = var.name_prefix
  registry_uri = local.registry_uri
  public_images_to_pull = var.public_images_to_pull
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.cluster.name
}



provider "kubernetes" {
  host =  aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.cluster.certificate_authority[0].data)
  token = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes = {
    host =  aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.cluster.certificate_authority[0].data)
    token = data.aws_eks_cluster_auth.cluster.token
  }
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

  name_prefix = "${var.name_prefix}-aws"
  cloud_provider = "aws"
  images_to_build = module.common_info.images_to_build
  model_storage_bucket_name = aws_s3_bucket.bucket.bucket
  k3s_service_accounts = module.common_info.k3s_service_accounts
  hf_token = var.hf_token
  models_to_download = var.models_to_download
  model_used_in_test=var.model_used_in_test
  image_used_in_test=var.image_used_in_test
  public_images_to_pull = module.common_info.public_images_to_pull

  depends_on = [
    helm_release.nvidia_device_plugin,
  ]

}

