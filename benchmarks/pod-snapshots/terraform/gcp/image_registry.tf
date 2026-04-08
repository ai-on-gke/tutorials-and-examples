resource "google_artifact_registry_repository" "repository" {
  location      = var.region
  repository_id = var.name_prefix
  format        = "DOCKER"
}

resource "google_service_account" "registry_pod_workload_sa" {
  account_id   = substr("${var.name_prefix}-registry-pod-sa",0 ,30)
}

# 2. Grant the GSA permissions to read from the Artifact Registry
resource "google_artifact_registry_repository_iam_member" "pod_sa_registry_reader" {
  project    = google_artifact_registry_repository.repository.project
  location   = google_artifact_registry_repository.repository.location
  repository = google_artifact_registry_repository.repository.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.registry_pod_workload_sa.email}"
}

# 3. Allow a specific Kubernetes Service Account (KSA) to impersonate the GSA
resource "google_service_account_iam_binding" "registry_workload_identity_binding" {
  for_each = { for sa in ["image-registry-helpers"]: sa=>module.common_info.k3s_service_accounts[sa] }
  service_account_id = google_service_account.registry_pod_workload_sa.id
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.name}]"
  ]
}
resource "google_service_account_iam_binding" "registry_token_creator_binding" {
  for_each = { for sa in ["image-registry-helpers"]: sa=>module.common_info.k3s_service_accounts[sa] }
  service_account_id = google_service_account.registry_pod_workload_sa.id
  role               = "roles/iam.serviceAccountTokenCreator"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.name}]"
  ]
}
