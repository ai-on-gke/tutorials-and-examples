project_id       = "<PROJECT_ID>"
cluster_name     = "<CLUSTER_NAME>"
cluster_location = "<CLUSTER_LOCATION>"


# Inference_pool 
inference_pool_name = "vllm-llama3-8b-instruct"

# Selector labels that has to match the labels on VLLM deployment pods, so that InferencePool object can find VLLM pods and take them under its control. 
inference_pool_match_labels = {
  app = "vllm-llama3-8b-instruct"
}
# Port of the VLLM server in the VLLM deployemnt pods.
inference_pool_target_port = 8000


# This is the list of models that can be accessed from the inference pool.
# Each element will create an InferenceModel resource (https://github.com/kubernetes-sigs/gateway-api-inference-extension/blob/3dd33b7ca893fc52ee8df2a4eeb01374d56e8488/site-src/reference/x-spec.md#inferencemodel)
inference_models = [

  {
    # Name of the InferenceModel resource object
    name = "llama3-base-model"

    # Name of the model in the pool by which it can be accessed.
    model_name = "meta-llama/Llama-3.1-8B-Instruct"

    #Criticality defines how important it is to serve the model compared to other models referencing the same pool.
    criticality = "Critical"
    # Name of the target InferencePol
    inference_pool_name = "vllm-llama3-8b-instruct"
  },
  {
    name                = "food-review"
    model_name          = "food-review"
    criticality         = "Standard"
    inference_pool_name = "vllm-llama3-8b-instruct"

    # The target_model represents a model or Lora adapter deployed in a VLLM server. If not specifieid, then it defaults to the `model_name`.
    # https://github.com/kubernetes-sigs/gateway-api-inference-extension/blob/3dd33b7ca893fc52ee8df2a4eeb01374d56e8488/site-src/reference/x-spec.md#targetmodel
    target_models = [
      {
        name   = "food-review-vllm"
        weight = 100
      }
    ]
  },
  {
    name                = "cad-fabricator"
    model_name          = "cad-fabricator"
    criticality         = "Standard"
    inference_pool_name = "vllm-llama3-8b-instruct"
    target_models = [
      {
        name   = "cad-fabricator-vllm"
        weight = 100
      }
    ]
  }
]

# Model armor

model_armor_templates = [
  {
    name = "model-armor-tutorial-default-template"
    sdp_settings = {
      basic_config = {
        filter_enforcement = "ENABLED"
      }
    }
  }
]


# This variable adds Model Armor settings to the GCPTrafficExtension resource that links the Model Armor template and the models from inference pool.
gcp_traffic_extension_model_armor_settings = [
  {
    # Model name from the Inference Pool. Declated in the `inference_models` variable.
    model = "food-review"

    # Model armor temlate to use on model response.
    model_response_template_name = "model-armor-tutorial-default-template"

    # Model armor temlate to use on user prompt.
    user_prompt_template_name = "model-armor-tutorial-default-template"
  },
]

# IP address
create_ip_address = true

# TLS certificate
domain                 = ""
use_tls                = false
create_tls_certificate = false

