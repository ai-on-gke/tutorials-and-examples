project_id  = "akvelon-gke-aieco"
network_name = "flowise-tf-akamalov"

cluster_name = "flowise-tf-akamalov"
cluster_location = "us-central1"

create_ip_address = false
ip_address_name = "akamalov-manual"

domain = "tambel.org"
use_tls = true
#create_tls_certificate = true
tls_certificate_name = "akamalov-manual"

# inference_pool 

inference_pool_name =  "vllm-llama3-8b-instruct"
inference_pool_match_labels = {
  app = "vllm-llama3-8b-instruct"
}

inference_pool_target_port = 8000

inference_models = [
  {
    name = "llama3-base-model"
    model_name = "meta-llama/Llama-3.1-8B-Instruct"
    criticality = "Critical"
    inference_pool_name = "vllm-llama3-8b-instruct"
  },
  {
    name = "food-review"
    model_name = "food-review"
    criticality = "Standard"
    inference_pool_name = "vllm-llama3-8b-instruct"
    target_models = [
      {
        name = "food-review-vllm"
        weight = 100
      }
    ]
  },
  {
    name = "cad-fabricator"
    model_name = "cad-fabricator"
    criticality = "Standard"
    inference_pool_name = "vllm-llama3-8b-instruct"
    target_models = [
      {
        name = "cad-fabricator-vllm"
        weight = 100
      }
    ]
  }
]

#http_route_path = "/v1/completions"
http_route_path = "/"

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

gcp_traffic_extension_model_armor_settings = [
  {
    model = "food-review-im"
    model_response_template_name = "model-armor-tutorial-default-template"
    user_prompt_template_name = "model-armor-tutorial-default-template"
  },
  {
    model = "meta-llama/Llama-3.1-8B-Instruct"
    model_response_template_name = "model-armor-tutorial-default-template"
    user_prompt_template_name = "model-armor-tutorial-default-template"
  }
]
