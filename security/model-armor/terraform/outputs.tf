output "ip_address" {
  value = local.ip_address
}
output "tls_certificate_dns_authorize_record_data" {
  value = local.create_tls_certificate ? module.tls_certificate[0].dns_authorize_record_data : null
}
output "tls_certificate_dns_authorize_record_name" {
  value = local.create_tls_certificate ? module.tls_certificate[0].dns_authorize_record_name : null
}

locals {
  url = var.use_tls ? "https://${var.domain}" : "http://${local.ip_address}"
}

output "url" {
  value = local.url
}
