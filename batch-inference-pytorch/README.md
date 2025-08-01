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


# Clone repository 
```
https://github.com/esaaren/tutorials-and-examples.git
cd tutorials-and-examples/batch-inference-pytorch/standard/setup
```

# View environment variables in setup/.env and adjust as needed

```
./setup.sh
```

# Authenticate Docker with Google Artifact Registry
```
gcloud auth configure-docker ${REGION}-docker.pkg.dev
```
# Build the image
```
docker build -f Dockerfile -t ${REGION}-docker.pkg.dev/${PROJECT}/torch-images/torch-ultra-job:latest .
```

# Push the image
```
docker push ${REGION}-docker.pkg.dev/${PROJECT}/torch-images/torch-ultra-job:latest
```

### 

### **Getting the dataset**

```
wget http://images.cocodataset.org/zips/val2017.zip
unzip val2017.zip 
python3 upload_images.py 
```

### **Launch the Job**

We simply apply our job to the cluster

```
envsubst < batch_inference.yaml | kubectl apply -f -
```

The job will be suspended until DWS provisions the A3 Ultra nodes, which may take a few minutes. You can monitor its status with:

```
kubectl describe job torch-inference-job
```

Once running, your describe job should look something like this, showing our job initially in a suspended state, followed by it being started once the resources were available and then successfully being resumed from its suspended state. 

```
  Type    Reason                 Age   From                        Message
  ----    ------                 ----  ----                        -------
  Normal  Suspended              10m   job-controller              Job suspended
  Normal  CreatedWorkload        10m   batch/job-kueue-controller  Created Workload: default/job-torch-inference-job-97e9b
  Normal  UpdatedAdmissionCheck  10m   batch/job-kueue-controller  dws-prov: Waiting for resources. Currently there are not enough resources available to fulfill the request.
  Normal  Started                90s   batch/job-kueue-controller  Admitted by clusterQueue dws-cluster-queue
  Normal  SuccessfulCreate       90s   job-controller              Created pod: torch-inference-job-0-zdscq
  Normal  SuccessfulCreate       90s   job-controller              Created pod: torch-inference-job-1-rgrbm
  Normal  Resumed                90s   job-controller              Job resumed

```

You'll see logs from all processes as they process their unique shards of data and write the results to CSV files in your GCS bucket. You can monitor the progress using

```
kubectl logs -l app=torch-inference-job -c job -f
```

Our final output data will look something like this

```
image_id,classification
413621,"teddy, teddy bear"
54259,"home theater, home theatre"
311496,balloon
...
```

Which is a list of our image ids in GCS followed by their classification. 

To cleanup, run: 

```
./setup/cleanup.sh 
```
