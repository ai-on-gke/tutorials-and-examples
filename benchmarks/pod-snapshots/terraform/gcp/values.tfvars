project_id = "akvelon-gke-aieco"

name_prefix = "gkebenchmarking"

region = "us-central1"
availability_zone = "a"

node_pools = {
  "utility-pool" = {
    machine_type = "n1-standard-16"
    min_count    = 1
    max_count    = 1
  },
  "gpu-pool" = {
    machine_type = "a3-highgpu-1g"
    min_count    = 1
    max_count    = 1
    gpu_enabled = true
    accelerator_type = "nvidia-h100-80gb"
    accelerator_count  = 1
  },
  "gvisor-pool" = {
    machine_type = "a3-highgpu-1g"
    min_count    = 1
    max_count    = 1
    gpu_enabled = true
    accelerator_type = "nvidia-h100-80gb"
    accelerator_count  = 1
    gvisor_enabled = true
  },
}
