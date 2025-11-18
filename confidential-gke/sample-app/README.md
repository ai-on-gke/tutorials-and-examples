This sample application demonstrates how to decrypt encrypted data in a TEE (Trusted Execution Environment) in GKE. 

Note: These manifests use configurations that won't run in typical GKE clusters.

# Encrypt data and push it to a GCS bucket
```
go mod tidy
go mod vendor
go build -o output/ ./cmd/tink-encryptor

export GCS_BUCKET_NAME_FOR_ENCRYPTED_DATA=<fill in>
export PROJECT_ID=<fill in>
export KEY_RING_LOCATION=<fill in>
export KEY_RING_NAME=<fill in>
export KEK_NAME=<fill in>

output/tink-encryptor \
--local_path=data/sample-plaintext.txt \
--gcs_blob_path=gs://${GCS_BUCKET_NAME_FOR_ENCRYPTED_DATA}/ciphertext_tink \
--kek_uri=gcp-kms://projects/$PROJECT_ID/locations/$KEY_RING_LOCATION/keyRings/$KEY_RING_NAME/cryptoKeys/$KEK_NAME
```

# Deploy Workload to decrypt data in the GCS bucket

## Create a Container Image that can decrypt the data.
```
docker build -t my-repo/my-image:tag .
docker push my-repo/my-image:tag
```

## Run Sample CPU workload in TEE

```
export GCS_BUCKET_NAME_FOR_ENCRYPTED_DATA=<fill in>
export PROJECT_ID=<fill in>
export KEY_RING_LOCATION=<fill in>
export KEY_RING_NAME=<fill in>
export KEK_NAME=<fill in>
export ENCRYPTED_FILENAME=<fill in>
export WIP_NAME=<the name of the workload identity pool used to authenticate for the GCS bucket>
export WIP_PROVIDER=<the provider being used to authenticate for the GCS bucket in the workload identity pool>
export SAMPLE_APP_IMAGE=<image created in the previous step>
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID | grep projectNumber | awk '{print $2}' | tr -d "'") 
export KEKURI=gcp-kms://projects/$PROJECT_ID/locations/$KEY_RING_LOCATION/keyRings/$KEY_RING_NAME/cryptoKeys/$KEK_NAME
export GCSPATH=gs://${GCS_BUCKET_NAME_FOR_ENCRYPTED_DATA}/${ENCRYPTED_FILENAME}

envsubst < manifests/sample-app.yaml | kubectl apply -f -
```

## Run Sample TPU workload in TEE

Make the following edits to `manifests/sample-tpu.yaml`

* Replace NODE_POOL_NAME with the name of the node pool that you want to run the workload on.
* Replace NGINX_IMAGE with a nginx image hosted in Artifact Registry.
* Replace TPU_IMAGE with a TPU jax image hosted in Artifact Registry.

```
kubectl apply -f manifests/sample-tpu.yaml
```
