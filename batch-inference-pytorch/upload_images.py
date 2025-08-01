# Copyright 2025 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os
import uuid
from google.cloud import storage
from concurrent.futures import ThreadPoolExecutor, as_completed

# Configure your GCS bucket and path
PROJECT_NAME = os.getenv("PROJECT",)
BUCKET_NAME = os.getenv("GSDATABUCKET")
GCS_PATH =  "path/"

# Local folder containing your images
LOCAL_FOLDER = "val2017"

# No. of parallel workers to upload
MAX_WORKERS = 16

def upload_single_file(local_file_path, filename, bucket_name, gcs_path):
    """
    Uploads a single image to GCS with the random hash naming convention.
    This function will be run in parallel by the executor.
    """
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)

        # Generate a random hash (UUID4 is a good choice for uniqueness)
        random_hash = uuid.uuid4().hex

        # Extract the base name (e.g., "1.jpg" from "00000001.jpg")
        original_file_number = os.path.splitext(filename)[0].lstrip('0')
        if not original_file_number:
            original_file_number = '0' # Or any other desired default

        # Construct the new GCS object name: <randomhashvalue>/1.jpg
        gcs_object_name = f"{gcs_path}{random_hash}/{original_file_number}.jpg"

        # Create a blob object and upload
        blob = bucket.blob(gcs_object_name)

        # Optional: Disable CRC32C checksums for faster transfer (use with caution)
        # blob.chunk_size = 2 * 1024 * 1024 # Example: Set a larger chunk size
        # blob.checksum = None # Disable CRC32C calculation on client side

        blob.upload_from_filename(local_file_path)

        print(f"Uploaded {filename} to gs://{bucket_name}/{gcs_object_name}")
        return True # Indicate success
    except Exception as e:
        print(f"Error uploading {filename}: {e}")
        return False # Indicate failure


def upload_with_random_hash_concurrently(local_folder, bucket_name, gcs_path, max_workers):
    """
    Uploads images from a local folder to GCS concurrently, adding a random hash.
    """
    image_files = []
    for filename in os.listdir(local_folder):
        if filename.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.bmp')):
            image_files.append(filename)

    if not image_files:
        print(f"No image files found in '{local_folder}'.")
        return

    print(f"Found {len(image_files)} image files. Starting concurrent uploads...")

    # Use ThreadPoolExecutor for concurrent I/O-bound tasks
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit tasks to the executor
        futures = {executor.submit(upload_single_file, os.path.join(local_folder, filename), filename, bucket_name, gcs_path): filename for filename in image_files}

        # Monitor the progress and results
        for future in as_completed(futures):
            filename = futures[future]
            if future.result():
                pass # Already printed success in upload_single_file
            else:
                print(f"Failed to upload {filename}.")

    print("All upload tasks submitted. Waiting for completion...")
    print("Upload process finished.")


if __name__ == "__main__":
    # Ensure you have authenticated to Google Cloud
    upload_with_random_hash_concurrently(LOCAL_FOLDER, BUCKET_NAME, GCS_PATH, MAX_WORKERS)