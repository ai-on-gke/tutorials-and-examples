provider "google" {
  project = var.project_id
}
# Create network and subnets for each region
resource "google_compute_network" "network" {
  name                    = "dws-network"
  auto_create_subnetworks = true

}


resource "google_container_cluster" "autopilot_dws_cluster" {


  name     = "dws-cluster-demo"
  location = var.region
  network  = google_compute_network.network.id

  enable_autopilot    = true
  deletion_protection = false
  release_channel {
    channel = "RAPID"
  }

}
# Create GKE Autopilot worker clusters


# Get Kubeconfig
resource "null_resource" "update_manager_kubeconfig" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOT
      gcloud container clusters get-credentials ${google_container_cluster.autopilot_dws_cluster.name} --region ${google_container_cluster.autopilot_dws_cluster.location} --project ${var.project_id}
    EOT
  }
  depends_on = [google_container_cluster.autopilot_dws_cluster]
}
