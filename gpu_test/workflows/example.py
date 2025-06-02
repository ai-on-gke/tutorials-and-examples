from flytekit import PodTemplate, ImageSpec, Resources, task, workflow
from kubernetes.client import V1PodSpec, V1Container
import torch

image = ImageSpec(
    base_image= "ghcr.io/flyteorg/flytekit:py3.10-1.10.2",
     name="pytorch",
     python_version="3.10",
     packages=["torch","kubernetes"],
     builder="default",
     registry="us-central1-docker.pkg.dev/akvelon-gke-aieco/vdjerek-flyte",
 )

pod = PodTemplate(
    pod_spec=V1PodSpec(
        containers = [V1Container(name="gpu")],
        node_selector = {"cloud.google.com/gke-accelerator":"nvidia-l4"})
)

@task(requests=Resources(gpu="1")
      , pod_template=pod 
      , limits=Resources(mem="8Gi", cpu="4")
      , container_image=image)
def gpu_available() -> bool:
   return torch.cuda.is_available() # returns True if CUDA (provided by a GPU) is available

@workflow
def gpu(name: str = 'gpu') -> bool:
    res = gpu_available()
    return res
