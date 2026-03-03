# Copyright 2025 Google LLC
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


#Note- for gemma models make sure you have preprocessor-config.json to hf checkpoint folder as its essential for nemorl to read model.

#!/bin/bash
WANDB_API_KEY='<YOUR_WANDB_API_KEY>' # Update this with your WANDB API key
HF_TOKEN='<YOUR_HF_TOKEN>' # Update this with your HF token
HF_CONVERTED_CHECKPOINT_PATH="/data/nemo_rl_gemma3_25b_2_27/hf2-28"
TP="4"
WORLD_SIZE=8

# --- Step 1: Find the Ray Head Pod ---
echo "Finding Ray head pod..."
export HEAD_POD_NAME=$(kubectl get pods --selector=ray.io/node-type=head -o jsonpath='{.items[0].metadata.name}')
if [ -z "$HEAD_POD_NAME" ]; then
    echo "Error: No running Ray head pod found. Please check your cluster."
    exit 1
fi
echo "Found head pod: $HEAD_POD_NAME"
echo ""

# --- Step 2: Define the Job Script to Run ---
# This is the script that will be executed *inside* the head pod.
# It assumes the 'uv venv' setup from the values.yaml is already done.
JOB_SCRIPT=$(cat <<EOF
set -ex
set -o pipefail

echo "--- Running on Ray Head Pod ($HOSTNAME) ---"
cd /opt/nemo-rl


echo "Setting environment variables..."
export WANDB_API_KEY=$WANDB_API_KEY
export HF_TOKEN=$HF_TOKEN
export HF_HOME=/opt/nemo-rl/

###-----Example to Eval Gemma3-27B on 1 node (8 GPUs)----------

uv run python examples/run_eval.py \
    --config examples/configs/evals/math_eval.yaml \
    generation.model_name=$HF_CONVERTED_CHECKPOINT_PATH \
    generation.temperature=0.6 \
    generation.vllm_cfg.max_model_len=32768 \
    generation.vllm_cfg.tensor_parallel_size=$TP \
    data.dataset_name=math500 \
    eval.num_tests_per_prompt=16 \
    cluster.gpus_per_node=8 2>&1 | tee eval_output.log


echo "--- Job Finished ---"
EOF
)

# --- Step 3: Execute the Job ---
echo "Submitting job to $HEAD_POD_NAME..."
echo "$JOB_SCRIPT" | tr -d '\r' | kubectl exec -i $HEAD_POD_NAME -c ray-head -- /bin/bash

echo ""
echo "Job submission complete."
