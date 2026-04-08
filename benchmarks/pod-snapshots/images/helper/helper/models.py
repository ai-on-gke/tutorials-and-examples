from abc import ABC, abstractmethod
import os
import shutil

from google.cloud import storage
import boto3
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from huggingface_hub import snapshot_download

import logging

logger = logging.getLogger("helper")

class ModelCopier(ABC):
    def copy_models_from_hf_to_bucket(self, models: list[str], model_path_prefix: str, remove_after_upload: bool=False):
        for model in models:
            self._copy_model_from_hf_to_bucket(model, model_path_prefix, remove_after_upload=remove_after_upload)

    def _copy_model_from_hf_to_bucket(self, model: str, model_path_prefix: str, remove_after_upload: bool):
        logger.info(f"🚀 Downloading {model} from Hugging Face...")

        local_dir = snapshot_download(
            repo_id=model,
            library_name="vllm",
            ignore_patterns=["*.msgpack", "*.h5", "*.bin"] # Only keep Safetensors for Run:ai
        )
        logger.info(f"✅ Downloaded to: {local_dir}")

        logger.info(f"☁️ Uploading to path {model_path_prefix}")
        

        for root, dirs, files in os.walk(local_dir):
            for file in files:
                local_path = os.path.join(root, file)
                
                relative_path = os.path.relpath(local_path, local_dir)
                
                dest_path = os.path.join(model_path_prefix, model, relative_path).replace("\\", "/")

                logger.info(f"Uploading {relative_path}...")
                try:
                    self._upload_file(local_path, dest_path)
                except Exception as e:
                    logger.info(f"❌ Failed to upload {relative_path}: {e}")
                    raise

        if remove_after_upload:
            logger.info("Remove model from the local storage")
            shutil.rmtree(local_dir)
        logger.info(f"✨ Success! Model {model} is uploaded")


    @abstractmethod
    def _upload_file(self, src_path:str, dest_path: str):
        pass

    @abstractmethod
    def close(self):
        pass

class GCPModelCopier(ModelCopier):
    def __init__(self, bucket_name: str):
        self.bucket_name = bucket_name
        self.client = storage.Client()
        self.bucket = self.client.bucket(bucket_name)

    def _upload_file(self, src_path:str, dest_path: str):
        blob = self.bucket.blob(dest_path)
        blob.upload_from_filename(src_path)

    def close(self):
        self.client.close()

class AWSModelCopier(ModelCopier):
    def __init__(self, bucket_name: str):
        self.bucket_name = bucket_name
        self.client = boto3.client('s3')

    def _upload_file(self, src_path:str, dest_path: str):
        self.client.upload_file(src_path, self.bucket_name, dest_path)

    def close(self):
        self.client.close()

class AzureModelCopier(ModelCopier):
    def __init__(
        self, 
        storage_account_name: str, 
        container_name: str,
    ):
        self.credential = DefaultAzureCredential()
        account_url = f"https://{storage_account_name}.blob.core.windows.net"
        self.blob_service_client = BlobServiceClient(account_url=account_url, credential=self.credential)
        self.container_client = self.blob_service_client.get_container_client(
            container=container_name,
        )

    def _upload_file(self, src_path:str, dest_path: str):
        with open(file=src_path, mode="rb") as data:
            self.container_client.upload_blob(
                name=dest_path, 
                data=data,
                overwrite=True,
                max_concurrency=8,
            )
    
    def close(self):
        self.container_client.close()
        self.blob_service_client.close()
        self.credential.close()


def download_models_into_bucket(
    cloud_provider_type: str,
    bucket_name: str,
    models: list[str],
    model_path_prefix: str,
    remove_after_upload: bool = False,
):

    match cloud_provider_type:
        case "gcp":
            uploader = GCPModelCopier(bucket_name)
        case "aws":
            uploader = AWSModelCopier(
                bucket_name=bucket_name,
            )
        case "azure":
            AZURE_STORAGE_ACCOUNT_NAME=os.environ["AZURE_STORAGE_ACCOUNT_NAME"]
            uploader = AzureModelCopier(
                storage_account_name=AZURE_STORAGE_ACCOUNT_NAME,
                container_name=bucket_name,
            )
        case _:
            raise ValueError(f"Unknown cloud provider type: {cloud_provider_type}")
    
    uploader.copy_models_from_hf_to_bucket(
        models,
        model_path_prefix,
        remove_after_upload =remove_after_upload,
    )

