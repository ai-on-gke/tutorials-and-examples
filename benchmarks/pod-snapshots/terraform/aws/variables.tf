variable "name_prefix" {
  type = string
}

variable "hf_token" {
  type = string
  sensitive = true
}

variable "region" {
  type=string
}

variable "node_pools" {
  type=map(object({
    machine_type = string
    min_count    = number
    max_count    = number
    gpu_enabled = optional(bool, false)
    labels = optional(map(string))
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
