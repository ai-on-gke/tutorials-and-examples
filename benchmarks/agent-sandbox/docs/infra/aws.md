# Create base infra for AWS   


1. Log in to aws:
   ```sh
   aws login
   ```

2. Create an environment variable with common base terraform command to shorten the following commands:
   ```sh
   TERRAFORM_CMD="terraform -chdir=./infra/aws"
   ```

3. Create a cluster and remaining infrastructure by applying the terraform config

   ```sh
   $TERRAFORM_CMD init
   $TERRAFORM_CMD apply -var-file values.tfvars
   ```

4. Configure kubectl to use a created cluster
   ```sh

   aws eks update-kubeconfig \
    --region $($TERRAFORM_CMD output -raw cluster_region) \
    --name $($TERRAFORM_CMD output -raw cluster_name)
   ```

5. Prepare the workloads.

   Make sure your workloads are using the needed runtime. In our case it is `kata-fc`.

   A special annotation also has to be added to a pod template in order to make it work in this runtime:

   ```yaml
   annotations: 
     io.containerd.cri.runtime-handler: "kata-fc"
   ```

6. Continue by going back to the [main page](../../README.md#TODO).


