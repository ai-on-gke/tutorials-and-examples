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
import csv
import io
import time
from pathlib import Path

import torch
import torch.distributed as dist
from torch.utils.data.distributed import DistributedSampler
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms
from transformers import ViTImageProcessor, ViTForImageClassification
from PIL import Image
from tqdm import tqdm
import sys

from dataflux_pytorch import dataflux_mapstyle_dataset

# --- CONFIGURATION ---
PROJECT_NAME = os.getenv("PROJECT")
BUCKET_NAME = os.getenv("GSDATABUCKET")
OUTPUT_PATH = os.getenv('OUTPUT_PATH')
IMAGE_PREFIX = "path/"
MODEL_ID = "google/vit-base-patch16-224"
BATCH_SIZE = 64
NUM_WORKERS = 12
OUTPUT_DIR = Path(f"{OUTPUT_PATH}/inference_results")

# --- HELPER FUNCTIONS  ---
def setup_distributed():
    dist.init_process_group(backend="nccl")
    torch.cuda.set_device(int(os.environ["LOCAL_RANK"]))

def cleanup_distributed():
    dist.destroy_process_group()

def get_image_id_from_path(gcs_path: str) -> str:
    return Path(gcs_path).stem

def create_collate_fn():
    def collate_fn(batch):
        image_ids = [item[0] for item in batch]
        image_tensors = torch.stack([item[1] for item in batch], dim=0)
        return image_ids, image_tensors
    return collate_fn

# This simple dataset works directly with the global indices provided by the DistributedSampler.
class DataFluxWrapperDataset(Dataset):
    """
    A lightweight wrapper for a DataFlux dataset. It is designed to
    work with PyTorch's DistributedSampler by using global indices to
    fetch data and metadata.
    """
    def __init__(self, dataflux_dataset, transform_fn=None):
        self.dataflux_dataset = dataflux_dataset
        self.transform_fn = transform_fn

    def __len__(self):
        # The length is the total number of objects in the dataset.
        return len(self.dataflux_dataset)

    def __getitem__(self, idx):
        # 1. Get object path from the full dataset's object list using the global index.
        object_path = self.dataflux_dataset.objects[idx][0]
        image_id = get_image_id_from_path(object_path)

        # 2. Use the same global index to get the raw image bytes via DataFlux.
        img_in_bytes = self.dataflux_dataset[idx]

        # 3. Apply transformations.
        image = Image.open(io.BytesIO(img_in_bytes)).convert("RGB")
        if self.transform_fn:
            tensor = self.transform_fn(image)
        else:
            tensor = image # Return PIL image if no transform

        return image_id, tensor

# --- Main Inference Function ---
def run_batch_inference():
    world_size = int(os.environ["WORLD_SIZE"])
    global_rank = int(os.environ["RANK"])
    local_rank = int(os.environ["LOCAL_RANK"])

    if global_rank == 0:
        OUTPUT_DIR.mkdir(exist_ok=True)
        print("--- 🚀 Starting batch inference job ---")

    # --- 2. Setup Model  ---
    if global_rank == 0: print("--- 🚀 Preparing model ---")
    processor = ViTImageProcessor.from_pretrained(MODEL_ID)
    model = ViTForImageClassification.from_pretrained(MODEL_ID).to(local_rank)
    model = DDP(model, device_ids=[local_rank], find_unused_parameters=True)
    model.eval()

    # --- 3. Setup Dataset and DataLoader ---
    if global_rank == 0: print("--- 🚀 Preparing image transform pipeline ---")
    image_transform_pipeline = transforms.Compose([
        transforms.Resize((processor.size['height'], processor.size['width'])),
        transforms.ToTensor(),
        transforms.Normalize(mean=processor.image_mean, std=processor.image_std)
    ])

    if global_rank == 0: print(f"--- 🚀 Preparing dataflux map style dataset with num_processes: {NUM_WORKERS} ---")
    base_dataflux_dataset = dataflux_mapstyle_dataset.DataFluxMapStyleDataset(
        project_name=PROJECT_NAME,
        bucket_name=BUCKET_NAME,
        config=dataflux_mapstyle_dataset.Config(
            prefix=IMAGE_PREFIX,
            sort_listing_results=False,
            num_processes=NUM_WORKERS
        ),
    )

    dataset = DataFluxWrapperDataset(
        dataflux_dataset=base_dataflux_dataset,
        transform_fn=image_transform_pipeline
    )
    
    if global_rank == 0: print(f"Found {len(dataset)} total images.")

    sampler = DistributedSampler(
        dataset,
        num_replicas=world_size,
        rank=global_rank,
        shuffle=False 
    )

    print(f"Rank {global_rank}: Sampler will give {len(sampler)} images to this process.")

    dataloader = DataLoader(
        dataset,
        batch_size=BATCH_SIZE,
        sampler=sampler, 
        collate_fn=create_collate_fn(),
        pin_memory=True, 
    )

    # --- 4. Run Inference and Write Sharded Results ---
    dist.barrier(device_ids=[local_rank])

    timestamp = time.strftime("%Y%m%d-%H%M%S")
    output_csv_path_shard = OUTPUT_DIR / f"results_{timestamp}_shard_{global_rank}.csv"

    with torch.no_grad(), open(output_csv_path_shard, 'w', newline='') as csvfile:
        csv_writer = csv.writer(csvfile)
        csv_writer.writerow(['image_id', 'classification'])

        progress_bar = tqdm(dataloader, desc=f"Rank {global_rank}", disable=(global_rank != 0))

        for image_ids, pixel_values_batch in progress_bar:
            pixel_values_batch = pixel_values_batch.to(local_rank, non_blocking=True)
            with torch.autocast(device_type="cuda", dtype=torch.bfloat16):
                outputs = model(pixel_values=pixel_values_batch)
            predicted_class_indices = outputs.logits.argmax(-1).cpu().numpy()

            id2label = model.module.config.id2label
            rows_to_write = [
                [image_id, id2label[class_idx]]
                for image_id, class_idx in zip(image_ids, predicted_class_indices)
            ]
            csv_writer.writerows(rows_to_write)

    print(f"--- ✅ Rank {global_rank} Complete. Results saved to: {output_csv_path_shard} ---")


if __name__ == "__main__":
    setup_distributed()
    try:
        run_batch_inference()
    finally:
        cleanup_distributed()
    sys.exit(0)