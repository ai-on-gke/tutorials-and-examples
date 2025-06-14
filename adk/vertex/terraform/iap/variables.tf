
variable "kubernetes_namespace" {
  type    = string
  default = "default"
}


variable "app_name" {
  type        = string
  description = "Name of the application"
  default     = "adk-vertex"
}



variable "k8s_app_service_name" {
  type        = string
  description = "Name of the K8s Backend Service"
  default     = "adk-agent"
}

variable "k8s_app_service_port" {
  type        = number
  description = "Name of the K8s Backend Service Port"
  default     = 80
}

variable "k8s_ingress_name" {
  type    = string
  default = "adk-ingress"
}

variable "k8s_managed_cert_name" {
  type        = string
  description = "Name for frontend managed certificate"
  default     = "adk-managed-cert"
}

variable "k8s_iap_secret_name" {
  type    = string
  default = "adk-iap-secret"
}

variable "k8s_backend_config_name" {
  type        = string
  description = "Name of the Backend Config on GCP"
  default     = "adk-backend-config"
}

variable "create_brand" {
  type        = bool
  description = "Create Brand OAuth Screen"
  default     = false
}

variable "support_email" {
  type        = string
  description = "Email for users to contact with questions about their consent"
  default     = "<email>"
}

variable "domain" {
  type        = string
  description = "Provide domain for ingress resource and ssl certificate."
  default     = "{IP_ADDRESS}.sslip.io"
}

variable "oauth_client_id" {
  type        = string
  description = "Client ID used for enabling IAP"
}

variable "oauth_client_secret" {
  type        = string
  description = "Client secret used for enabling IAP"
  sensitive   = false
}

variable "members_allowlist" {
  type = list(string)
}
