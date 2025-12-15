/**
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

terraform {
  required_providers {
    google-private = {
      source = "google.com/providers/google-private"
      version = "0.0.251208"   # Match the `google-private` provider version
    }
  }
}

provider "google-private" {
  project = var.project_id
  region  = var.location
}

resource "google_container_cluster" "cgke_cluster" {
  provider = google-private  # Can use public "google" provider for GKE clusters

  project  = var.project_id
  location = var.location
  name     = var.cluster_name

  initial_node_count = 1

  node_config {
    machine_type = "e2-medium"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  min_master_version = var.cluster_version

  # for IP aliasing
  ip_allocation_policy {}

  datapath_provider = "ADVANCED_DATAPATH"

  release_channel {
    channel = "UNSPECIFIED"
  }
  
  deletion_protection = true  # Recommended to avoid unexpected cluster replacement
}

# ----- CPU Control Node Pool -----
resource "google_container_node_pool" "cpu_control_pool" {
  provider   = google-private
  
  project    = var.project_id
  location   = var.location
  name       = "cpu-control-pool"

  node_locations = [var.runner_zone]
  cluster    = google_container_cluster.cgke_cluster.name
  version    = var.cluster_version
  node_count = 1

  node_config {
    machine_type = "n2-standard-80"
    disk_type    = "pd-balanced"

    labels = {
      "cloud.google.com/gke-dpv2-unified-cni" = "cni-migration"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    runner_pool_control {
	    mode = "CONFIDENTIAL"
    }
  }

  management {
    auto_upgrade = false
    auto_repair  = false
  }
}

# ----- CPU Linked Runner Node Pool -----
resource "google_container_node_pool" "cpu_linked_pool" {
  provider   = google-private

  project    = var.project_id
  location   = var.location
  name       = "cpu-linked-pool"
  
  node_locations = [var.runner_zone]
  cluster    = google_container_cluster.cgke_cluster.name
  version    = var.cluster_version
  node_count = 3

  node_config {
    machine_type = "e2-medium"

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    service_account = "${var.runner_sa}@${var.project_id}.iam.gserviceaccount.com"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    image_type = "CUSTOM_CONTAINERD"
    node_image_config {
      image         = var.cgke_image_name
      image_project = var.cgke_image_project
    }

    runner_pool_config {
      control_node_pool = google_container_node_pool.cpu_control_pool.name
	    attestation {
        mode       = "ENABLED"
        tee_policy = var.tee_policy
      }
    }
  }

  management {
    auto_upgrade = false
    auto_repair  = false
  }
}

# ----- TPU Control Node Pool -----
resource "google_container_node_pool" "tpu_control_pool" {
  provider   = google-private
  
  project    = var.project_id
  location   = var.location
  name       = "tpu-control-pool"

  node_locations = [var.runner_zone]
  cluster    = google_container_cluster.cgke_cluster.name
  version    = var.cluster_version
  node_count = 1

  node_config {
    machine_type = "n2-standard-80"
    disk_type    = "pd-balanced"

    labels = {
      "cloud.google.com/gke-dpv2-unified-cni" = "cni-migration"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    runner_pool_control {
	    mode = "CONFIDENTIAL"
    }
  }

  management {
    auto_upgrade = false
    auto_repair  = false
  }
}

# ----- TPU Linked Runner Node Pool -----
# Demostrate ct5lp-hightpu-4t instances with a 4x4 TPU topology
resource "google_container_node_pool" "tpu_linked_pool" {
  provider   = google-private

  project    = var.project_id
  location   = var.location
  name       = "tpu-linked-pool"
  
  cluster        = google_container_cluster.cgke_cluster.name
  node_locations = [var.runner_zone]
  version        = var.cluster_version
  node_count     = 4

  placement_policy {
    type         = "COMPACT"
    tpu_topology = "4x4"
  }

  node_config {
    machine_type = "ct5lp-hightpu-4t"
    reservation_affinity {
      consume_reservation_type = "SPECIFIC_RESERVATION"
      key                      = "compute.googleapis.com/reservation-name"
      values = [
        "projects/${var.reservation_project_id}/reservations/${var.reservation_name}"
      ]
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    service_account = "${var.runner_sa}@${var.project_id}.iam.gserviceaccount.com"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    image_type = "CUSTOM_CONTAINERD"
    node_image_config {
      image         = var.cgke_image_name
      image_project = var.cgke_image_project
    }

    runner_pool_config {
      control_node_pool = google_container_node_pool.tpu_control_pool.name
	    attestation {
        mode = "ENABLED"
        tee_policy = var.tee_policy
      }
    }
  }

  management {
    auto_upgrade = false
    auto_repair  = false
  }

  network_config {
    # --- [OPTIONAL] For additional node network ---

    additional_node_network_configs {
      network    = google_compute_network.extra_network.name
      subnetwork = google_compute_subnetwork.extra_subnetwork.name
    }
    # --- [End of OPTIONAL node network section] ---
  }
}
