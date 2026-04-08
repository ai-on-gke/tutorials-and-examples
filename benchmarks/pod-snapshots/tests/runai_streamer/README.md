1. Create a GKE cluster:
```bash
CLUSTER_NAME=CLUSTER_NAME
gcloud container clusters create-auto $CLUSTER_NAME
```

2. Create or use an existing GCS bucket (you can use [this one](https://console.cloud.google.com/storage/browser/dimadrogovoz-tf-backend?project=akvelon-gke-aieco&pageState=(%22StorageObjectListTable%22:(%22f%22:%22%255B%255D%22))) since it has models [here](https://console.cloud.google.com/storage/browser/dimadrogovoz-tf-backend/models?project=akvelon-gke-aieco&pageState=(%22StorageObjectListTable%22:(%22f%22:%22%255B%255D%22))). If you decided to use this bucket, you can skip WIF step and just create service account `dima-vllm-sa` and namespace `dima-vllm-ns` inside your GKE cluster).

3. Grant permission via WIF:

```bash
export BUCKET_NAME=BUCKET_NAME
export PROJECT_ID=PROJECT_ID
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID \
    --format 'get(projectNumber)')
    
gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME \
    --member="principal://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$PROJECT_ID.svc.id.goog/subject/ns/$NAMESPACE/sa/$KSA_NAME" \
    --role="roles/storage.bucketViewer"
    
gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME \
    --member="principal://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$PROJECT_ID.svc.id.goog/subject/ns/$NAMESPACE/sa/$KSA_NAME" \
    --role="roles/storage.objectUser"
```

4. Create a namespace and a service account in your GKE cluster:
```bash
kubectl create namespace $NAMESPACE
kubectl create serviceaccount $KSA_NAME \
    --namespace=$NAMESPACE
```

5. Deploy the `charts/scaletimer`

6. If you use your custom GCS bucket, you need to upload a model to your GCS bucket:

```bash
python -m venv venv
. venv/bin/activate
pip install -r requirements.txt
python load_model_to_gcs_bucket.py
```

7. Change `<...>` values in the `model-streamer-gcs.yaml` and apply it. Wait about 2-5 minutes.

8. Run the `benchmark.sh` script in this folder:

```bash
export CLUSTER_NAME=CLUSTER_NAME
export ZONE=ZONE
export NAMESPACE=NAMESPACE
export DEPLOYMENT=vllm-streamer-deployment
export LOAD_GENERATION_DURATON=10m
export VLLM_SERVICE=vllm-service
export SCALETIMER_SERVICE=scaletimer-bm

sh ./benchmark.sh $DEPLOYMENT $CLUSTER_NAME $LOAD_GENERATION_DURATON $VLLM_SERVICE $SCALETIMER_SERVICE $ZONE $NAMESPACE
```

9. The final output should look like this:

```log
-|------|------
         Aggregated                                                         5100   5500   5700  15000  22000  28000  43000  43000  43000  44000  44000   2285

Port forwarding scaletimer service: scaletimer-bm...
scaletimer port-forward established (PID: 96807)

=========================================
Pod Startup Times for deployment: vllm-streamer-deployment
=========================================
Pod: vllm-streamer-deployment-5874684d9-gmgl5           Startup:  129.0s
Pod: vllm-streamer-deployment-5874684d9-r7zq4           Startup:  182.0s
Cleaning up...
```
