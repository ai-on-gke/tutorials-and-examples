FROM debian:trixie-slim

RUN DEBIAN_FRONTEND=noninteractive apt update && \
  apt install -y curl \
  jq \
  unzip \
  containerd \
  skopeo \
  python3 \
  python3-venv && \
  apt clean

RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz && \
  tar -xf google-cloud-cli-linux-x86_64.tar.gz && \
  ./google-cloud-sdk/install.sh && \
  rm -r google-cloud-cli-linux-x86_64.tar.gz
RUN ln -s /google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
  unzip awscliv2.zip && \
  ./aws/install && \
  rm -r ./aws awscliv2.zip 

RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash && apt clean 



RUN python3 -m venv /venv
ADD requirements.txt /tmp
RUN /venv/bin/python3 -m pip install --no-cache-dir -r /tmp/requirements.txt && rm /tmp/requirements.txt

ADD helper /helper


