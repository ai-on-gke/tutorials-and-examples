# Create base infra for GCP

## Prerequisites

- [gcloud CLI](https://cloud.google.com/sdk/docs/install) installed and authenticated
- A GCP project with billing enabled and sufficient GPU quota

1. Authenticate and set your project:

   ```sh
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. Create an environment variable with the base Terraform command to shorten the following commands:

   ```sh
   TERRAFORM_CMD="terraform -chdir=./terraform/gcp"
   ```

3. Create a `values.tfvars` file in `./terraform/gcp/` with your configuration. Example:

   ```hcl
   project_id        = "your-gcp-project-id"
   default_name      = "gkebenchmarking"
   region            = "us-central1"
   availability_zone = "a"

   node_pools = {
     "utility-pool" = {
       machine_type = "n1-standard-16"
       min_count    = 1
       max_count    = 1
     },
     "gpu-pool" = {
       machine_type     = "g2-standard-4"
       min_count        = 1
       max_count        = 1
       gpu_enabled      = true
       accelerator_type = "nvidia-l4"
       accelerator_count = 1
     },
   }
   ```

   Adjust `machine_type`, `accelerator_type`, and pool counts to match your quota and workload requirements. The GPU driver is installed automatically (`LATEST` version).

4. Create the cluster and remaining infrastructure:

   ```sh
   $TERRAFORM_CMD init
   $TERRAFORM_CMD apply -var-file values.tfvars
   ```

5. Configure `kubectl` to use the created cluster:

   ```sh
   gcloud container clusters get-credentials \
     $($TERRAFORM_CMD output -raw cluster_name) \
     --location $($TERRAFORM_CMD output -raw cluster_location)
   ```

6. Continue by going back to the [main README](../../README.md).