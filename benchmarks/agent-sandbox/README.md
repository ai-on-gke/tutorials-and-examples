
# Create cluster and remianing infra

For GCP:
   1. Create an environment variable with common base terraform command to shorten the following commands:
      ```sh
      TERRAFORM_CMD="terraform -chdir=./infra/gcp"
      ```
   
   2. Create a cluster and remaining infrastructure by applying the terraform config
   
      ```sh
      $TERRAFORM_CMD init
      $TERRAFORM_CMD apply -var-file values.tfvars
      ```
   
   3. Configure kubectl to use a created cluster
   
      ```sh
      gcloud container clusters get-credentials $($TERRAFORM_CMD output -raw cluster_name) --location $($TERRAFORM_CMD output -raw cluster_location)
      ```

Instructions for other cloud providers can be found here:
   * [AWS](./docs/infra/aws.md)
   * [Azure](./docs/infra/azure.md)


# Run tests

Go to a test under the `tests` directory and follow instructions from a local README.
