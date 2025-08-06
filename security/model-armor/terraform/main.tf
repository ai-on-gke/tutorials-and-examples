resource "google_compute_subnetwork" "proxy_only" {
  count   = var.create_proxy_only_subnetwork == true ? 1 : 0
  project = var.project_id
  name    = var.proxy_only_subnetwork_name
  region  = var.cluster_location
  network = data.google_container_cluster.cluster.network
  #network                 = var.network_name
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
  ip_cidr_range = "10.127.0.0/23"
}

resource "google_compute_address" "ip_address" {
  count        = var.create_ip_address == true ? 1 : 0
  project      = var.project_id
  name         = var.ip_address_name
  address_type = "EXTERNAL"
  region       = "us-central1"
  ip_version   = "IPV4"
}

data "google_compute_address" "ip_address" {
  count   = var.create_ip_address == true ? 0 : 1
  project = var.project_id
  region  = var.cluster_location
  name    = var.ip_address_name
}

locals {
  ip_address      = var.create_ip_address == true ? google_compute_address.ip_address[0].address : data.google_compute_address.ip_address[0].address
  ip_address_name = var.create_ip_address == true ? google_compute_address.ip_address[0].name : data.google_compute_address.ip_address[0].name
}

locals {
  create_tls_certificate = var.use_tls && var.create_tls_certificate
}

module "tls_certificate" {
  count  = local.create_tls_certificate ? 1 : 0
  source = "github.com/ai-on-gke/common-infra//common/modules/managed-tls-certificate?ref=main"

  project_id       = var.project_id
  location         = var.cluster_location
  domain           = var.domain
  certificate_name = var.tls_certificate_name
}



module "inference_gateway" {
  providers = {
    kubernetes = kubernetes.cluster
    helm       = helm.cluster
  }
  source                      = "github.com/ai-on-gke/common-infra//common/modules/inference-gateway?ref=main"
  project_id                  = var.project_id
  cluster_name                = var.cluster_name
  cluster_location            = var.cluster_location
  kubernetes_namespace        = var.kubernetes_namespace
  crds_version                = var.inference_gateway_crds_version
  gateway_name                = var.gateway_name
  inference_pool_name         = var.inference_pool_name
  inference_pool_match_labels = var.inference_pool_match_labels
  inference_pool_target_port  = var.inference_pool_target_port
  inference_models            = var.inference_models
  ip_address_name             = local.ip_address_name
  tls_certificate_name        = var.use_tls ? var.tls_certificate_name : ""
  domain                      = var.domain
  http_route_name             = var.http_route_name
  http_route_path             = var.http_route_path
  rendered_templates_path     = "${path.module}/../gen"
  depends_on = [
    google_compute_subnetwork.proxy_only,
    google_compute_address.ip_address,
    module.tls_certificate,
  ]
}

resource "google_model_armor_template" "template" {
  for_each    = { for template in var.model_armor_templates : template.name => template }
  project     = var.project_id
  location    = var.cluster_location
  template_id = each.value.name

  filter_config {
    rai_settings {
      dynamic "rai_filters" {
        for_each = each.value.rai_settings.rai_filters
        content {
          filter_type      = rai_filters.value.filter_type
          confidence_level = rai_filters.value.confidence_level
        }
      }
    }

    sdp_settings {
      basic_config {
        filter_enforcement = each.value.sdp_settings.basic_config.filter_enforcement
      }
    }

    pi_and_jailbreak_filter_settings {
      filter_enforcement = each.value.pi_and_jailbreak_filter_settings.filter_enforcement
      confidence_level   = each.value.pi_and_jailbreak_filter_settings.confidence_level
    }

    malicious_uri_filter_settings {
      filter_enforcement = each.value.malicious_uri_filter_settings.filter_enforcement
    }
  }
  template_metadata {
    custom_prompt_safety_error_code = each.value.template_metadata.custom_prompt_safety_error_code
  }
}

locals {
  gcp_traffic_extension_model_armor_settings = [
    for settings in var.gcp_traffic_extension_model_armor_settings : {
      model                      = settings.model
      model_response_template_id = "projects/${var.project_id}/locations/${var.cluster_location}/templates/${settings.model_response_template_name}"
      user_prompt_template_id    = "projects/${var.project_id}/locations/${var.cluster_location}/templates/${settings.user_prompt_template_name}"
    }
  ]
}


resource "local_file" "model_armor_gcp_traffic_extension" {
  content = templatefile(
    "${path.module}/templates/gcp-traffic-extension.yaml.tpl",
    {
      NAME                 = var.gcp_traffic_extension_name
      NAMESPACE            = var.kubernetes_namespace
      GATEWAY_NAME         = var.gateway_name
      MODEL_ARMOR_SETTINGS = jsonencode(local.gcp_traffic_extension_model_armor_settings)
    }
  )
  filename = "${path.module}/../gen/gcp-traffic-extension.yaml"
}

resource "kubernetes_manifest" "model_armor_gcp_traffic_extension" {
  provider = kubernetes.cluster
  manifest = provider::kubernetes::manifest_decode(local_file.model_armor_gcp_traffic_extension.content)
  depends_on = [
    module.inference_gateway,
    google_model_armor_template.template,
    local_file.model_armor_gcp_traffic_extension
  ]
  lifecycle {
    replace_triggered_by = [
      local_file.model_armor_gcp_traffic_extension.content,
    ]
  }
}
