models_to_download = {
  "qwen3-32b" = {
    name="Qwen/Qwen3-32B"
  }
}

model_used_in_test="qwen3-32b"


public_images_to_pull = {
  "vllm" = {
    source_registry = "docker.io"
    source_repository = "vllm/vllm-openai"
    tag = "v0.18.0"
  }
}

image_used_in_test = "vllm"

