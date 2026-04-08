variable "name_prefix" {
  type = string
}

variable "hf_token" {
  type=string
  sensitive=true
}

variable "cloud_provider" {
  type = string
}

variable "images_to_build" {
  type=map(object({
    repository = string
    full_name = string
    tag = string
    build_context = string
    platform = string
  }))
}

variable "public_images_to_pull" {
  type=map(object({
    source_full_name = string
    repository = string
    full_name = string
  }))
}

variable "model_storage_bucket_name" {
  type=string
}

variable "k3s_service_accounts" {
  type = map(object({
    name = string
    namespace=string
  }))
}

output "test" {
  value=var.k3s_service_accounts
}

variable "registry_extra_info" {
  type=object({
    service_account_annotations=optional(map(string), {})
    pod_labels=optional(map(string), {})
    pod_environment_variables=optional(map(string), {})
  })
  default={}
}

variable "model_storage_extra_info" {
  type=object({
    service_account_annotations=optional(map(string), {})
    pod_labels=optional(map(string), {})
    pod_environment_variables=optional(map(string), {})
  })
  default={}
}

variable "pod_snapshot_extra_info" {
  type=object({
      bucket_name = string
      service_account_annotations=optional(map(string), {})
    })
  default=null
}



variable "models_to_download" {
  type=map(object({
    name=string
  }))
}

variable "model_used_in_test" {
  type=string
}

variable "image_used_in_test" {
  type=string
}

