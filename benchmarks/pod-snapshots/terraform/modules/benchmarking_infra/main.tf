resource "kubernetes_namespace_v1" "namespaces" {
  for_each = toset([for ns in values(var.k3s_service_accounts)[*].namespace: ns if ns != "default"])
  metadata {
    name = each.key
  }
}

