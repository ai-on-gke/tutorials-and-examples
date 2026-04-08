default_name = "agent-sandbox-benchmarking"

subscription_id="9c94ae9c-af2a-4d43-8bd5-d158e0cdff88"
resource_group_name = "Akvelon"
location = "westus"

node_pools = {
  "utility-pool" = {
    machine_type = "Standard_D8ds_v5"
    min_count    = 1
    max_count    = 1
  },
  ## https://github.com/hashicorp/terraform-provider-azurerm/issues/31665
  #"sandbox-pool" = {
  #  machine_type = "Standard_D4s_v3"
  #  min_count    = 3
  #  max_count    = 3
  #  os-sku = "AzureLinux"
  #  workload_runtime="KataVmIsolation"
  #},
  #"gpu-pool" = {
  #  machine_type = "Standard_NC24ads_A100_v4"
  #  min_count    = 1
  #  max_count    = 1
  #  gpu_enabled = true
  #},
}
