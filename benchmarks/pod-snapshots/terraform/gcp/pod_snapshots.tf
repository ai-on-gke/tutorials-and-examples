resource "google_storage_bucket" "pod_snapshot_storage_bucket" {
  name          = "${var.name_prefix}-pod-snapshot"
  location      = var.region
  force_destroy = true
  uniform_bucket_level_access = true
  soft_delete_policy {
    retention_duration_seconds = 0
  }
  hierarchical_namespace {
    enabled = true
  }

}

resource "google_service_account" "pod_snapshot_storage_workload_sa" {
  account_id   = substr("${var.name_prefix}-pod-snapshot-store-sa",0 ,30)
}

#resource "google_project_iam_custom_role" "custom_gcs_role" {
#  role_id     = "customGcsManagerRole"
#  
#  title = "test"
#  #project     = var.project_id
#
#  permissions = [
#    "storage.objects.get",
#    "storage.objects.create",
#    "storage.objects.delete",
#    "storage.buckets.get",
#    "storage.folders.create"
#  ]
#}

#resource "google_storage_bucket_iam_member" "pod_snapshot_storage_writer" {
#  #for_each = toset(["roles/storage.objectUser", "roles/storage.bucketViewer"])
#  bucket = google_storage_bucket.pod_snapshot_storage_bucket.name
#  #role       = each.key
#  role = google_project_iam_custom_role.custom_gcs_role.id 
#  member     = "serviceAccount:${google_service_account.pod_snapshot_storage_workload_sa.email}"
#}

resource "google_storage_bucket_iam_member" "test" {
  for_each = toset(["roles/storage.objectUser", "roles/storage.bucketViewer"])
  bucket = google_storage_bucket.pod_snapshot_storage_bucket.name
  role       = each.key
  member     = "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/akvelon-gke-aieco.svc.id.goog/subject/ns/default/sa/pod-snapshots-ksa"
}


resource "google_service_account_iam_binding" "pod_snapshot_storage_binding" {
  
  for_each = toset(["roles/iam.workloadIdentityUser"])
  service_account_id = google_service_account.pod_snapshot_storage_workload_sa.id
  role               = each.key
  members = [
    #"serviceAccount:${var.project_id}.svc.id.goog[${module.common_info.k3s_service_accounts[sa].namespace}/${module.common_info.k3s_service_accounts[sa].name}]"
    "serviceAccount:${var.project_id}.svc.id.goog[default/pod-snapshots-ksa]"
  ]
}
