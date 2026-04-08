resource "kubernetes_secret_v1" "huggingface_token" {
  metadata {
    name = "hf-token"
    namespace = "default"
  }

  type = "Opaque"

  data = {
    "token" = var.hf_token
  }
}


locals {
  cloud_provider_to_runai_streamer_model_url_prefix={
    "gcp" = "gs",
    "aws" = "s3",
    "azure" = "az",
  }
  runai_streamer_model_url_prefix=local.cloud_provider_to_runai_streamer_model_url_prefix[var.cloud_provider]

  runia_test_service_account_info = var.k3s_service_accounts["runai_vllm_test"]

  cloud_provider_to_addition_tolerations = {
    "gcp" = []
    "aws" = [],
    "azure" = [
      {
        key = "sku",
        operator = "Equal",
        value = "gpu",
        effect = "NoSchedule",
      },
    ]
  }

  additional_toleration_patches = [
    for t in local.cloud_provider_to_addition_tolerations[var.cloud_provider]:
    {
      op= "add"
      path = "/spec/template/spec/tolerations/-"
      value = t
    }
  ]
}

resource "kubernetes_service_account_v1" "runai_streamer_test_service_account" {
  metadata {
    name =local.runia_test_service_account_info.name
    namespace = local.runia_test_service_account_info.namespace
    annotations = merge(
      {},
      var.model_storage_extra_info.service_account_annotations
    )
  }
  depends_on = [
    kubernetes_namespace_v1.namespaces
  ]

}

resource "local_file" "baseline_test_patch" {
  filename = "${path.module}/../../../tests/baseline/overlays/${var.cloud_provider}/patch.yaml"
  content = yamlencode(
    concat(
      [
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
      local.additional_toleration_patches,
    )
  )
}

resource "local_file" "runai_streamer_test_patch" {
  filename = "${path.module}/../../../tests/runai_streamer/overlays/${var.cloud_provider}/patch.yaml"
  content = yamlencode(
    concat(
      [
        {
          op = "add",
          path = "/spec/template/spec/serviceAccountName"
          value = kubernetes_service_account_v1.runai_streamer_test_service_account.metadata[0].name
        },
        {
          op = "add",
          path = "/spec/template/spec/containers/0/args/0"
          value = "--model=${local.runai_streamer_model_url_prefix}://${var.model_storage_bucket_name}/models/${var.models_to_download[var.model_used_in_test].name}"
        },
        {
          op= "replace"
          path = "/spec/template/spec/containers/0/image"
          value =var.public_images_to_pull[var.image_used_in_test].full_name
        }
      ],
      [ 
        for name, value in var.model_storage_extra_info.pod_environment_variables: {
          op= "add"
          path = "/spec/template/spec/containers/0/env/-"
          value = {
            name = name,
            value = value,
          }
        }
      ],
      [ 
        for name, value in var.model_storage_extra_info.pod_labels: {
          op= "add"
          path = "/spec/template/metadata/labels/${replace(name, "/", "~1")}"
          value = value
        }
      ],
      local.additional_toleration_patches,
    )
  )
}




