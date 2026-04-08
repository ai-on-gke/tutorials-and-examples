locals {
  images_to_build_names = [
    "helper",
    "exporter",
  ]

  images_dir = abspath("${path.module}/../../../images")
  built_images_tag = "latest"

  images_to_build = { for image_name in local.images_to_build_names:
    image_name => {
      repository = "${var.image_name_prefix}/${image_name}"
      full_name = "${var.registry_uri}/${var.image_name_prefix}/${image_name}:${local.built_images_tag}"
      tag = local.built_images_tag
      build_context = "${local.images_dir}/${image_name}"
      platform = "linux/amd64"
    }
  }

  #public_images_to_pull_info = {
  #  "vllm" = {
  #    source_registry = "docker.io"
  #    source_repository = "vllm/vllm-openai"
  #    tag = "v0.18.0"
  #  }
  #}

  public_images_to_pull = {
    for key, img in var.public_images_to_pull:
    key=>{
      source_full_name = "${img.source_registry}/${img.source_repository}:${img.tag}"
      repository = "${var.image_name_prefix}/${img.source_repository}"
      full_name = "${var.registry_uri}/${var.image_name_prefix}/${img.source_repository}:${img.tag}"
    }
  }
  
  helpers_namespace = "benchmarking-helpers-ns"

  k3s_service_accounts = {
    "image-registry-helpers" = {
      name = "image-registry-helpers-sa"
      namespace = local.helpers_namespace
    },
    "model-storage-helpers" = {
      name = "model-storage-helpers-sa"
      namespace = local.helpers_namespace
    },
    "runai_vllm_test" = {
      name = "runai-vllm-test"
      namespace = "default"
    }
  }
}
