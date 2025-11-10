This sample application is meant to be used together with a separate guide 
and not as a standalone repository to help demonstrate how to decrypt and
encrypt data in a TEE(Trusted Execution Environment) in GKE.

# Encrypt data and push it to a GCS bucket
```
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

## Create Container Image that can decrypt the data.
```
docker build -t my-repo/my-image:tag .
docker push my-repo/my-image:tag
```

## Run Sample CPU workload in TEE
NOTE: Follow the guide to sign the newly created image before running it in the TEE.

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
NOTE: Follow the guide to sign the nginx and tpu images before running it in the TEE.

```
export SIGNED_NGINX_IMAGE=<fill in>
export SIGNED_TPU_IMAGE=<fill in>

envsubst < manifests/sample-tpu.yaml | kubectl apply -f -
```

