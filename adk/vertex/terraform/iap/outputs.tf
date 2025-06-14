
output "app_public_ip" {
  value = module.iap_auth.ip_address
}

output "app_url" {
  value = "https://${module.iap_auth.domain}"
}

output "k8s_managed_cert_name" {
  value = var.k8s_managed_cert_name
}
