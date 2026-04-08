# Performance Testing & Agent Sandbox Setup

This `README.md` covers how to provision your cloud environments, install the necessary tools, and execute performance tests using `clusterloader2` across different cloud providers.

---

## 1. Cloud Environment Setup

Each cloud provider requires specific steps to configure the infrastructure and ensure logging is captured correctly. Complete the setup for your target provider before moving to installation.

### GCP
1. Navigate to `infra/gcp`.
2. Apply the Terraform files to provision your infrastructure.

### Azure
1. Navigate to `docs/infra` and follow the `README` to create your initial Azure cluster.
2. Add the target node pool for Kata containers:
    ```bash
    az aks nodepool add \
      --cluster-name $(terraform -chdir=./infra/azure output -raw cluster_name) \
      --resource-group $(terraform -chdir=./infra/azure output -raw resource_group_name) \
      --name katapool \
      --os-sku AzureLinux \
      --node-vm-size Standard_D16s_v6 \
      --workload-runtime KataVmIsolation \
      --enable-cluster-autoscaler \
      --min-count 5 \
      --max-count 5 \
      --node-count 5
    ```
    > **Note:** To delete this node pool later, run:
    > ```bash
    > az aks nodepool delete \
    >   --cluster-name $(terraform -chdir=infra/azure output -raw cluster_name) \
    >   --resource-group $(terraform -chdir=infra/azure output -raw resource_group_name) \
    >   --name katapool
    > ```
3. Navigate to your cluster in the Azure portal and deploy logging using the default parameters.
4. **Verify Logging:** Deploy any pod that outputs to stdout (e.g., `echo 'test message'`). In the Azure portal's **Logs** section, run the following filter to ensure logs are captured:
    ```kusto
    ContainerLogV2
    | where PodNamespace == 'default'
    | project TimeGenerated, PodName, LogMessage
    ```

### AWS
1. Navigate to `infra/aws` and apply the Terraform files.
2. Go to your EKS Add-ons and enable **CloudWatch** for your cluster.
3. **Grant IAM Permissions:**
    * Go to the AWS EKS Console, click your cluster, and navigate to the **Compute** tab.
    * Click your Node Group and locate the **Node IAM Role ARN** (e.g., `eksctl-...-NodeInstanceRole-...`). Click it to open the IAM console.
    * On the IAM Role page, select **Add permissions** -> **Attach policies**.
    * Search for exactly `CloudWatchAgentServerPolicy`, check the box, and click **Add permissions**.
4. **Restart Fluent Bit:** Fluent Bit uses exponential backoff. To apply the new permissions immediately, kill the existing pods so Kubernetes spins up fresh ones:
    ```bash
    kubectl delete pods -n amazon-cloudwatch -l k8s-app=fluent-bit
    ```
5. **Verify Logging:** Wait about 30 seconds, then check the logs of the new pods:
    ```bash
    kubectl logs -n amazon-cloudwatch daemonset/fluent-bit --tail=20
    ```
    Deploy a pod that outputs to stdout (e.g., `echo 'test message'`) and run `run-eks-small.sh`. It should successfully create a JSON file containing your target logs.

---

## 2. Installation & Prerequisites

Once your cluster is ready, install the required manifests, testing tools, and local dependencies.

### Apply Manifests
Install the agent sandbox manifests and required extensions:
```bash
kubectl apply -f ../../releases_assets/manifest.yaml
kubectl apply -f ../../releases_assets/extensions.yaml
```

### Build clusterloader2 (CL2)
Download and compile the Kubernetes performance testing tool:
```bash
git clone https://github.com/kubernetes/perf-tests.git
cd perf-tests/clusterloader2
go build -o clusterloader2 ./cmd
cd ../../
```

### Setup Python Environment
Create a virtual environment and install dependencies required for testing and log parsing:
```bash
python -m venv venv
source venv/bin/activate
pip install numpy
```

---

## 3. Running the Tests

Ensure your Python virtual environment is activated. You can run tests using the provided wrapper scripts or execute `clusterloader2` manually.

### Automated Test Scripts
Use the script corresponding to your cloud provider:

```bash
# GKE
bash ./run-gke.sh $KUBECONFIG $CLUSTER_NAME

# AKS
bash ./run-aks.sh $KUBECONFIG $CLUSTER_NAME $WORKSPACE_ID

# EKS
bash ./run-eks.sh $KUBECONFIG $CLUSTER_NAME $REGION
```

Each command will generate a new folder inside `metric-gathering/` folder like this: `metric-gathering/test-results-<PROVIDER>`.
