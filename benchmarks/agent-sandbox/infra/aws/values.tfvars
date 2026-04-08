default_name = "agent-sandbox-benchmarking"

node_pools = {
  "utility-pool" = {
    machine_type = "t3.medium"
    min_count    = 1
    max_count    = 1
  },
  "sandbox-pool" = {
    machine_type = "c5.metal"
    min_count    = 1
    max_count    = 1
    setup_devmapper_pool = true
    labels = {
      "benchmarking-sandbox-pool": "true"
    }
  },
}
