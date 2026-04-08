resource "google_storage_bucket" "model_storage_bucket" {
  name          = var.name_prefix
  location      = var.region
  force_destroy = true
  uniform_bucket_level_access = true
}

resource "google_service_account" "model_storage_workload_sa" {
  account_id   = substr("${var.name_prefix}-model-stor-pod-sa",0 ,30)
}

resource "google_storage_bucket_iam_member" "model_storage_writer" {
  for_each = toset(["roles/storage.objectUser", "roles/storage.bucketViewer"])
  bucket = google_storage_bucket.model_storage_bucket.name
  role       = each.key
  member     = "serviceAccount:${google_service_account.model_storage_workload_sa.email}"
}


resource "google_service_account_iam_binding" "model_storage_binding" {
  
  for_each = toset(["roles/iam.workloadIdentityUser", "roles/iam.serviceAccountTokenCreator"])
  service_account_id = google_service_account.model_storage_workload_sa.id
  role               = each.key
  members = [
    for sa in ["model-storage-helpers", "runai_vllm_test"]:
    "serviceAccount:${var.project_id}.svc.id.goog[${module.common_info.k3s_service_accounts[sa].namespace}/${module.common_info.k3s_service_accounts[sa].name}]"
  ]
}
