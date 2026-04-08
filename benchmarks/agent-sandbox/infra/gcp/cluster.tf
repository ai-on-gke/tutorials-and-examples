resource "google_compute_network" "vpc" {
  name                    = "${var.default_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${google_compute_network.vpc.name}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.1.0.0/24" 
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.2.0.0/16"
  }
  lifecycle {
    ignore_changes = [secondary_ip_range]
  }
}

locals {
  cluster_location = var.region
}

resource "google_container_cluster" "cluster" {
  name     = local.cluster_name
  location = local.cluster_location
  
  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  networking_mode = "VPC_NATIVE"

  deletion_protection=false

  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "node_pools" {
  for_each = var.node_pools
  name       = "${var.default_name}-${each.key}"
  location       = local.cluster_location
  node_locations = each.value.node_locations
  cluster        = google_container_cluster.cluster.name
  node_count = each.value.min_count

  max_pods_per_node = each.value.max_pods_per_node

  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  node_config {
    image_type   = "cos_containerd"
    machine_type = each.value.machine_type
    disk_size_gb = "100"
    disk_type    = each.value.disk_type

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    dynamic "sandbox_config" {
      for_each = each.value.gvisor_enabled? [1]: []
      content {
        sandbox_type="gvisor"
      }
    }
    dynamic "guest_accelerator" {
      for_each = each.value.gpu_enabled? [1]: []
      content {
        type  = each.value.accelerator_type
        count = each.value.accelerator_count
        gpu_driver_installation_config {
          gpu_driver_version = "LATEST"
        }
      }
    }
  }
}
