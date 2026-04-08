variable "subscription_id" {
  type=string
}

variable "resource_group_name" {
  type=string
}

variable "location" {
  type=string
}

variable "default_name" {
  type = string
}

variable "node_pools" {
  type=map(object({
    machine_type = string
    min_count    = number
    max_count    = number
    gpu_enabled = optional(bool, false)
    os_sku = optional(string)
    workload_runtime = optional(string)

  }))
}
