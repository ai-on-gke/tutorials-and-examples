module "gke_cluster" {
  source            = "github.com/ai-on-gke/common-infra/common/infrastructure?ref=main"
  project_id        = var.project_id
  cluster_name      = var.cluster_name
  cluster_location  = var.cluster_location
  autopilot_cluster = var.autopilot_cluster
  private_cluster   = var.private_cluster
  create_network    = false
  network_name      = var.network_name
  subnetwork_name   = var.subnetwork_name
  subnetwork_region = var.subnetwork_region
  subnetwork_cidr   = var.subnetwork_cidr
  ray_addon_enabled = false
  depends_on        = [module.custom_network]
}

resource "google_artifact_registry_repository" "image_repo" {
  project = var.project_id
  location      = var.image_repository_location
  repository_id = var.image_repository_name
  format        = "DOCKER"
}

resource "google_artifact_registry_repository_iam_binding" "registry_binding_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.image_repo.location
  repository = google_artifact_registry_repository.image_repo.repository_id
  role       = "roles/artifactregistry.reader"
  members = [
    "serviceAccount:${module.gke_cluster.service_account}",
  ]
  depends_on = [google_artifact_registry_repository.image_repo, module.gke_cluster]
}

locals {
  image_repository_full_name = "${var.image_repository_location}-docker.pkg.dev/${var.project_id}/${var.image_repository_name}"
}

resource "local_file" "agent_manifest" {
  content = templatefile(
    "${path.module}/templates/secured-agent.yaml.tftpl",
    {
      IMAGE_NAME = local.image_repository_full_name
    }
  )
  filename = "${path.module}/../gen/secured-agent.yaml"
}
