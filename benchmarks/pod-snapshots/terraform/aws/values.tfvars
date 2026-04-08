name_prefix = "gkebenchmarking"

region = "us-east-1"
node_pools = {
  "utility-pool" = {
    machine_type = "t3.2xlarge"
    min_count    = 1
    max_count    = 1
  },
  "gpu-pool" = {
    machine_type = "p5.4xlarge"
    min_count    = 1
    max_count    = 1
    gpu_enabled = true
  },
}
