locals {
  pod_snapshot_enabled = var.cloud_provider == "gcp"
}

resource "kubernetes_service_account_v1" "pod_snapshot_service_account" {
  count = local.pod_snapshot_enabled? 1: 0
  metadata {
    name = "pod-snapshots-ksa"
    namespace = "default"
    annotations = merge(
      {},
      var.pod_snapshot_extra_info.service_account_annotations,
      #{
      #  "iam.gke.io/gcp-service-account"="gkebenchmarking-pod-snapshot-s@akvelon-gke-aieco.iam.gserviceaccount.com"
      #},
    )
  }
  depends_on = [
    kubernetes_namespace_v1.namespaces
  ]
}

resource "local_file" "pod_snapshot_config_patch" {
  count = local.pod_snapshot_enabled? 1: 0
  filename = "${path.module}/../../../tests/snapshots/pod-storage-config/overlays/${var.cloud_provider}/patch.yaml"
  content = yamlencode(
      [
        {
          op = "add",
          path = "/spec/snapshotStorageConfig/gcs/bucket"
          value = var.pod_snapshot_extra_info.bucket_name
        },
      ],
  )
}

resource "local_file" "pod_snapshot_vllm_patch" {
  count = local.pod_snapshot_enabled? 1: 0
  filename = "${path.module}/../../../tests/snapshots/vllm-pod-snapshots/overlays/${var.cloud_provider}/patch.yaml"
  content = yamlencode(
      [
        {
          op = "add",
          path = "/spec/template/spec/serviceAccountName"
          value = kubernetes_service_account_v1.pod_snapshot_service_account[0].metadata[0].name
        },
        {
          op = "add",
          path = "/spec/template/spec/containers/0/args/0"
          value = "--model=${var.models_to_download[var.model_used_in_test].name}"
        },
        {
          op= "replace"
          path = "/spec/template/spec/containers/0/image"
          value =var.public_images_to_pull[var.image_used_in_test].full_name
        }
      ],
  )
}
