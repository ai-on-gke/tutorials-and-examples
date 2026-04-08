variable "default_name" {
  type = string
}

variable "region" {
  type=string
  default="us-east-1"
}

variable "cluster_name" {
  type =string
  description="The name of a cluster. On empty default the 'default_name' variable will be used"
  default="" 
}

variable "network_name" {
  type=string
  description="The name of a vpc. On empty default the 'default_name' variable will be used"
  default="" 
}
variable "network_subnet_name" {
  type=string
  description="The name of a vpc subnet. On empty default the 'default_name' + suffix variable will be used"
  default="" 
}

variable "node_pools" {
  type=map(object({
    machine_type = string
    min_count    = number
    max_count    = number
    gpu_enabled = optional(bool, false)
    arm_enabled = optional(bool, false)
    setup_devmapper_pool: optional(bool, false)
    labels = optional(map(string))
  }))
}
