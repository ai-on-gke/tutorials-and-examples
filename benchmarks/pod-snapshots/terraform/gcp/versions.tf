terraform {
  required_providers {
    google = {
      source  = "hashicorp/google-beta"
      version = "~> 7.26.0"
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
