variable "project_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cluster_location" {
  type = string
}

variable "create_proxy_only_subnetwork" {
  type    = bool
  default = true
}

variable "proxy_only_subnetwork_name" {
  type    = string
  default = "model-armor-tutorial-proxy-only"
}

variable "inference_gateway_crds_version" {
  type    = string
  default = "v0.5.1"
}

variable "kubernetes_namespace" {
  type    = string
  default = "default"
}

variable "gateway_name" {
  type    = string
  default = "model-armor-tutorial-gateway"
}

variable "create_ip_address" {
  type    = bool
  default = true
}

variable "ip_address_name" {
  type    = string
  default = "model-armor-tutorial-gateway"
}

variable "domain" {
  type    = string
  default = ""
}

variable "use_tls" {
  type    = bool
  default = false
}

variable "create_tls_certificate" {
  type    = bool
  default = false
  validation {
    condition     = var.create_tls_certificate == true && var.domain != "" || var.create_tls_certificate == false
    error_message = "Domain name is required to create TLS certificate."
  }
}

variable "tls_certificate_name" {
  type    = string
  default = "model-armor-tutorial-cert"
}



variable "inference_pool_name" {
  type = string
}

variable "inference_pool_match_labels" {
  type = map(string)
}

variable "inference_pool_target_port" {
  type = number
}

variable "inference_models" {
  type = list(object({
    name        = string
    model_name  = string
    criticality = string
    target_models = optional(
      list(object({
        name   = string
        weight = number
      })),
      []
    )
  }))
}

variable "http_route_name" {
  type    = string
  default = "model-armor-tutorial-http-route"
}

variable "http_route_path" {
  type    = string
  default = "/"
}

variable "model_armor_templates" {
  type = list(object({
    name = string
    rai_settings = optional(
      object({
        rai_filters = list(object({
          filter_type      = string
          confidence_level = string
        }))
      }),
      {
        rai_filters = [
          {
            filter_type      = "HATE_SPEECH"
            confidence_level = "MEDIUM_AND_ABOVE"
          },
          {
            filter_type      = "SEXUALLY_EXPLICIT"
            confidence_level = "MEDIUM_AND_ABOVE"
          },
          {
            filter_type      = "HARASSMENT"
            confidence_level = "MEDIUM_AND_ABOVE"
          },
          {
            filter_type      = "DANGEROUS"
            confidence_level = "MEDIUM_AND_ABOVE"
          }
        ]
      }
    )
    sdp_settings = optional(
      object({
        basic_config = object({
          filter_enforcement = string
        })
      }),
      {
        basic_config = {
          filter_enforcement = "DISABLED"
        }
      }
    )
    pi_and_jailbreak_filter_settings = optional(
      object({
        filter_enforcement = string
        confidence_level   = string
      }),
      {
        filter_enforcement = "ENABLED"
        confidence_level   = "MEDIUM_AND_ABOVE"
      }
    )
    malicious_uri_filter_settings = optional(
      object({
        filter_enforcement = string
      }),
      {
        filter_enforcement = "DISABLED"
      }
    )
    template_metadata = optional(
      object({
        custom_prompt_safety_error_code = number
      }),
      {
        custom_prompt_safety_error_code = 403
      }
    )
  }))
}

variable "gcp_traffic_extension_name" {
  type    = string
  default = "model-armor-tutorial-gcp-traffic-extension"
}

variable "gcp_traffic_extension_model_armor_settings" {
  type = list(object({
    model                        = string
    model_response_template_name = string
    user_prompt_template_name    = string
  }))
}




