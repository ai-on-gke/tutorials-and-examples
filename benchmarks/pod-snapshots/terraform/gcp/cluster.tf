locals {
  cluster_location = "${var.region}-${var.availability_zone}"
}

resource "google_container_cluster" "cluster" {
  name     = var.name_prefix
  location = local.cluster_location
  
  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  networking_mode = "VPC_NATIVE"

  deletion_protection=false

  remove_default_node_pool = true
  initial_node_count       = 1
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    pod_snapshot_config {
      enabled=true
    }
  }
}
resource "google_service_account" "gke_node_sa" {
  account_id   = "${var.name_prefix}-node-sa"
}

resource "google_artifact_registry_repository_iam_member" "gke_sa_repo_reader" {
  project    = google_artifact_registry_repository.repository.project
  location   = google_artifact_registry_repository.repository.location
  repository = google_artifact_registry_repository.repository.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.gke_node_sa.email}"
}
resource "google_container_node_pool" "node_pools" {
  for_each = var.node_pools
  name       = "${var.name_prefix}-${each.key}"
  location = local.cluster_location
  cluster    = google_container_cluster.cluster.name
  node_count = each.value.min_count

  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  node_config {
    service_account = google_service_account.gke_node_sa.email
    image_type   = "cos_containerd"
    machine_type = each.value.machine_type
    disk_size_gb = "100"
    disk_type    = "pd-balanced"

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

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
    dynamic "sandbox_config" {
      for_each = each.value.gvisor_enabled? [1]: []
      content {
        type="GVISOR"
      }
    }

    ephemeral_storage_local_ssd_config {
      local_ssd_count  = 2
    }
  }
  depends_on = [
    google_artifact_registry_repository_iam_member.gke_sa_repo_reader,
  ]
}

resource "terraform_data" "ready_cluster" {
  depends_on = [
    google_container_cluster.cluster,
    google_container_node_pool.node_pools,
  ]
}
