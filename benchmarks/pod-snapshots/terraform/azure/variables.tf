variable "name_prefix" {
  type = string
}

variable "hf_token" {
  type = string
  sensitive = true
}

variable "subscription_id" {
  type=string
}

variable "resource_group_name" {
  type=string
}

variable "location" {
  type=string
}

variable "node_pools" {
  type=map(object({
    machine_type = string
    min_count    = number
    max_count    = number
    gpu_enabled = optional(bool, false)
    gpu = optional(
      object({
        enabled = optional(bool, false)
        install_driver = optional(bool, false)
      }),
      {}
    )

    os_sku = optional(string)
    workload_runtime = optional(string)

  }))
}

variable "models_to_download" {
  type=map(object({
    name=string
  }))
}

variable "model_used_in_test" {
  type=string
}

variable "public_images_to_pull" {
  type=map(object({
    source_registry = string
    source_repository = string
    tag = string
  }))
}

variable "image_used_in_test" {
  type=string
}
