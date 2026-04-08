# Install Azure AKS cluster

1. Log in to Azure using its CLI:
   ```sh
   az login
   ```

2. Create an environment variable with common base terraform command to shorten the following commands:
   ```sh
   TERRAFORM_CMD="terraform -chdir=./infra/azure"
   ```

3. Create a cluster and remaining infrastructure by applying the terraform config

   ```sh
   $TERRAFORM_CMD init
   $TERRAFORM_CMD apply -var-file values.tfvars
   ```

4. Manually add the node poll with Kata Containers isolation runtime. The terraform Azure provider (at the current moment) does not have this feature (https://github.com/hashicorp/terraform-provider-azurerm/issues/31665):
   ```sh
   az aks nodepool add \
      --cluster-name $($TERRAFORM_CMD output -raw cluster_name) \
      --resource-group $($TERRAFORM_CMD output -raw resource_group_name) \
      --name katapool \
      --node-vm-size Standard_D64s_v4 \
      --os-sku AzureLinux \
      --workload-runtime KataVmIsolation \
      --enable-cluster-autoscaler \
      --min-count 1 \
      --max-count 1 \
      --node-count 1
   ```

5. To access the cluster from kubectl, update your kubeconfig by running:
   ```sh
   az aks get-credentials \
      --name $($TERRAFORM_CMD output -raw cluster_name) \
      --resource-group $($TERRAFORM_CMD output -raw resource_group_name)
   ```

6. Continue by going back to the [main page](../../README.md#TODO).
