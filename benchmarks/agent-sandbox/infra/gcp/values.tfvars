project_id = "akvelon-gke-aieco"
default_name = "agent-sandbox-benchmarking"

region = "us-central1"
node_pools = {
  "utility-pool" = {
    machine_type = "n1-standard-16"
    min_count    = 1
    max_count    = 1
  },
  "sandbox-pool" = {
    machine_type = "n1-standard-16"
    min_count    = 1
    max_count    = 1
    gvisor_enabled = true
    max_pods_per_node = 256
    node_locations = ["us-central1-a"]

  },
  #"gpu-pool" = {
  #  machine_type = "g2-standard-4"
  #  min_count    = 1
  #  max_count    = 1
  #  gpu_enabled = true
  #  accelerator_type = "nvidia-l4"
  #  accelerator_count  = 1
  # max_pods_per_node = 256
  # node_locations = ["us-central1-a"]
  #},
}
