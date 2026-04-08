name_prefix = "gkebenchmarking"

subscription_id="9c94ae9c-af2a-4d43-8bd5-d158e0cdff88"
resource_group_name = "Akvelon"
location = "westus"

node_pools = {
  "utility-pool" = {
    machine_type = "Standard_D8ds_v5"
    min_count    = 1
    max_count    = 1
  },
  "gpu-pool" = {
    machine_type = "Standard_NC24ads_A100_v4"
    min_count    = 1
    max_count    = 1
    gpu = {
      enabled = true
      install_driver = true
    }
  },
}
