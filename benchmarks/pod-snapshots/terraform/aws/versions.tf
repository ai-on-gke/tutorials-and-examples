terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.39.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "~> 3.0.1"
    }
    helm = {
      source = "hashicorp/helm"
      version = "~> 3.1.1"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.0.0"
    }
  }
}
