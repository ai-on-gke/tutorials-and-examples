variable "project_id" {
  type=string
}

variable "default_name" {
  type = string
}

variable "region" {
  type=string
}

variable "node_pools" {
  type=map(object({
    machine_type = string
    min_count    = number
    max_count    = number
    node_locations = optional(list(string))
    disk_type    = optional(string, "pd-standard")
    gvisor_enabled = optional(bool, false)
    gpu_enabled = optional(bool, false)
    accelerator_type = optional(string)
    accelerator_count  = optional(number)
    max_pods_per_node = optional(number)
  }))
}
