variable "image_name_prefix" {
  type = string
}

variable "registry_uri" {
  type = string
}

variable "public_images_to_pull" {
  type=map(object({
    source_registry = string
    source_repository = string
    tag = string
  }))
}

