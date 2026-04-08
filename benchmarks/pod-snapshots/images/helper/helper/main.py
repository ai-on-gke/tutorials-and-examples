#!/usr/bin/env python3

import argparse
import logging
import json

from models import download_models_into_bucket 
from images import (
    pull_images_with_ctr,
    copy_public_images_to_registry,
)

logging.basicConfig(level=logging.ERROR)
logger = logging.getLogger("helper")
logger.setLevel(logging.INFO)

    
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--cloud-provider-type", required=True, choices=["gcp", "aws", "azure"])
    subparsers = parser.add_subparsers(dest='command', required=True)

    download_model_parser = subparsers.add_parser("download_models")
    download_model_parser.add_argument("--bucket-name", required=True)
    download_model_parser.add_argument("--model-path-prefix", help="The folder inside the bucket")
    download_model_parser.add_argument("--models", help="Comma-separated list of model names", required=True)
    download_model_parser.add_argument("--remove-after-upload",action="store_true", help="Remove model that is already uploaded to the bucket from local storage")

    image_pull_parser = subparsers.add_parser("pull_images")
    image_pull_parser.add_argument("--images", required=True)

    image_copy_parser = subparsers.add_parser("copy_public_images")
    image_copy_parser.add_argument("--images", required=True)

    args = parser.parse_args()

    if args.command == "download_models":
        download_models_into_bucket(
            args.cloud_provider_type,
            bucket_name=args.bucket_name,
            models=args.models.split(","),
            model_path_prefix=args.model_path_prefix,
        )
    elif args.command == "pull_images":
        pull_images_with_ctr(
            args.cloud_provider_type,
            args.images.split(","),
        )
    elif args.command == "copy_public_images":
        copy_public_images_to_registry(
            args.cloud_provider_type,
            json.loads(args.images),
        )
    else:
        logger.error(f"Unknown command: '{args.command}'")
        exit(1)


    logger.info("Completed succesfully")

