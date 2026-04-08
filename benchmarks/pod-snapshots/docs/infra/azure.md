# Create base infra for Azure   

1. Log in to Azure:
   ```sh
   az login
   ```
2. Specify the 'CLOUD_PROVIDER' environment variable:
   ```sh
   CLOUD_PROVIDER=azure
   ```

3. Set a shorthand for the Terraform command:
   ```sh
   TERRAFORM_CMD="terraform -chdir=./terraform/${CLOUD_PROVIDER}"
   ```

4. Initialize the terraform configuration:
   ```sh
   $TERRAFORM_CMD init
   ```

5. Apply the terraform config just for the cluster.
   ```sh
   $TERRAFORM_CMD apply -var-file ../common.tfvars -var-file values.tfvars -target=terraform_data.ready_cluster
   ```

6. Make current terminal session use previously created kubeconfig file:
   ```sh
   export KUBECONFIG="./kubeconfig_${CLOUD_PROVIDER}"
   ```

7. Configure kubectl to use a created cluster and make it save kubeconfig to a previously specified path:
   ```sh
   KUBECONFIG="${KUBECONFIG_PATH}" az aks get-credentials \
      --name $($TERRAFORM_CMD output -raw cluster_name) \
      --resource-group $($TERRAFORM_CMD output -raw resource_group_name)
   ```

8. Apply the rest of the terraform config:
   ```sh
   $TERRAFORM_CMD apply -var-file ../common.tfvars -var-file values.tfvars
   ```

8. Continue by going back to the [main page](../../README.md).
