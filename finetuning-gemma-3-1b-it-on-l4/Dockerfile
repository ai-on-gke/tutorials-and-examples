# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM nvidia/cuda:13.4.2-runtime-ubuntu22.04

RUN apt-get update && \
    apt-get -y --no-install-recommends install python3-dev gcc python3-pip git && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
    accelerate==1.6.0 bitsandbytes==0.45.5 \
    datasets==3.5.0 transformers==4.51.3 \
    peft==0.15.1 trl==0.16.1 \
    torch==2.5.1 torchvision==0.20.1

COPY finetune.py /finetune.py

ENV PYTHONUNBUFFERED 1

CMD python3 /finetune.py --device cuda
