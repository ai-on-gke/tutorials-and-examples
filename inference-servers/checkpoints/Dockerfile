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

# Ubuntu:24.04
# Use Ubuntu 24.04 from Docker Hub - needed for its default Python 3.12,
# since maxtext's setup.sh now requires 3.12+ (was fine on 22.04's 3.10 when
# this Dockerfile was first written).
# https://hub.docker.com/_/ubuntu/tags?page=1&name=24.04
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
# Ubuntu 24.04 marks the system Python as externally-managed (PEP 668).
# maxtext's setup.sh installs against system Python with both pip and uv
# (uv for the tpu/gpu requirements files), and each tool has its own,
# differently-named env var to bypass the externally-managed-environment
# restriction - without both, installs fail partway through setup.sh.
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ENV UV_BREAK_SYSTEM_PACKAGES=1

RUN apt -y update && apt install -y --no-install-recommends \
    ca-certificates \
    git \
    python3 \
    python3-pip \
    curl \
    gnupg

# --ignore-installed: the apt-installed pip has no RECORD file (it's tracked
# by dpkg, not pip's own metadata), so a plain `pip install --upgrade pip`
# fails trying to uninstall it first.
RUN python3 -m pip install --upgrade pip --ignore-installed pip

# Same RECORD-file conflict as above, but for setuptools/wheel this time -
# and this one happens *inside* maxtext's own setup.sh (`pip install -U
# setuptools wheel uv`), which is pulled fresh from GitHub and can't be
# edited here. Purge the dpkg-owned copies up front so pip has nothing left
# to (fail to) uninstall when setup.sh runs.
RUN apt -y remove python3-setuptools python3-wheel 2>/dev/null || true

RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
RUN apt -y update && apt install -y google-cloud-cli

RUN git clone https://github.com/AI-Hypercomputer/maxtext.git && \
cd /maxtext && \
bash src/dependencies/scripts/setup.sh

RUN pip install kaggle && \
pip install huggingface_hub[cli] && \
pip install google-jetstream && \
pip install llama-stack && \
pip install torch && \
pip install grain-nightly

COPY checkpoint_converter.sh /usr/bin/
RUN chmod +x /usr/bin/checkpoint_converter.sh
ENTRYPOINT ["/usr/bin/checkpoint_converter.sh"]
