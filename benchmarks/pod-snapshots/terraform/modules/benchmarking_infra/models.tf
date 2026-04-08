locals {
  model_storage_service_account_info = var.k3s_service_accounts["model-storage-helpers"]
}

resource "kubernetes_service_account_v1" "model_downloader_sa" {
  metadata {
    name = local.model_storage_service_account_info.name
    namespace = local.model_storage_service_account_info.namespace
    annotations = merge(
      {},
      var.model_storage_extra_info.service_account_annotations
    )
  }
  depends_on = [
    kubernetes_namespace_v1.namespaces
  ]

}

resource "kubernetes_secret_v1" "model_downloader_huggingface_token" {
  metadata {
    name = "hf-token"
    namespace = local.model_storage_service_account_info.namespace
  }

  type = "Opaque"

  data = {
    "hf_token" = var.hf_token
  }
}

resource "kubernetes_job_v1" "model-downloader" {
  metadata {
    name      = "model-downloader"
    namespace = local.model_storage_service_account_info.namespace
    
    labels = {
      app = "model-downloader"
    }
  }

  spec {
    backoff_limit = 4
    
    template {
      metadata {
        labels = merge(
          {
            app = "model-downloader"
          },
          var.model_storage_extra_info.pod_labels
        )
      }

      spec {
        service_account_name = local.model_storage_service_account_info.name
        container {
          name    = "model-downloader"
          image       = docker_registry_image.registry_images["helper"].name
          image_pull_policy = "Always"
          command = [
            "bash",
            "-c",
            <<EOF
            #sleep infinity
            /venv/bin/python3 /helper/main.py \
              --cloud-provider-type "${var.cloud_provider}" \
              download_models \
              --bucket-name ${var.model_storage_bucket_name} \
              --models '${join(",", values(var.models_to_download)[*].name)}' \
              --model-path-prefix "models" \
              --remove-after-upload
            EOF
          ]
          env {
            name = "HF_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.model_downloader_huggingface_token.metadata[0].name
                key  = "hf_token"
              }
            }
          }
          env {
            name = "HF_HUB_ENABLE_HF_TRANSFER"
            value = "0"
          }

          dynamic "env" {
            for_each = var.model_storage_extra_info.pod_environment_variables
            content {
              name = env.key
              value = env.value
            }
          }
        }

        # Jobs must have a restart_policy of "Never" or "OnFailure"
        restart_policy = "Never"
      }
    }
  }
  timeouts {
    create = "30m"
    update = "30m"
  }
  wait_for_completion=true
  depends_on = [
    docker_registry_image.registry_images["helper"],
  ]
}
