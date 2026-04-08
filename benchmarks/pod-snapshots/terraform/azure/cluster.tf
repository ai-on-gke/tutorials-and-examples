resource "azurerm_kubernetes_cluster" "cluster" {
  name                = var.name_prefix
  location = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  dns_prefix          = var.name_prefix

  default_node_pool {
    name       = "system"
    node_count = 1
    vm_size    = "Standard_D8ds_v5"
    vnet_subnet_id = azurerm_subnet.subnet.id
    temporary_name_for_rotation = "defaulttemp"
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }
  network_profile {
    network_plugin = "azure"
  }

  tags = {
    Environment = "Production"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
}

resource "azurerm_kubernetes_cluster_node_pool" "node_pool" {
  for_each = var.node_pools
  name                  = replace(each.key, "-", "")
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cluster.id
  
  vnet_subnet_id = azurerm_subnet.subnet.id
  
  vm_size = each.value.machine_type
  os_sku =  each.value.os_sku
  auto_scaling_enabled = true
  min_count = each.value.min_count
  max_count = each.value.max_count
  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
  }
  gpu_driver = each.value.gpu.install_driver? "Install": "None"
  node_taints = concat(
    [],
    each.value.gpu.enabled? ["sku=gpu:NoSchedule"]: []
  )
  
  workload_runtime=each.value.workload_runtime
}

resource "kubernetes_namespace_v1" "gpu_resources" {
  metadata {
    name = "gpu-resources"
  }
  depends_on = [
    azurerm_kubernetes_cluster.cluster,
  ]
}

resource "kubernetes_daemon_set_v1" "nvidia_device_plugin" {
  metadata {
    name      = "nvidia-device-plugin-daemonset"
    namespace = kubernetes_namespace_v1.gpu_resources.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        name = "nvidia-device-plugin-ds"
      }
    }

    strategy {
      type = "RollingUpdate"
    }

    template {
      metadata {
        labels = {
          name = "nvidia-device-plugin-ds"
        }
      }

      spec {
        priority_class_name = "system-node-critical"

        toleration {
          key      = "sku"
          operator = "Equal"
          value    = "gpu"
          effect   = "NoSchedule"
        }

        container {
          name  = "nvidia-device-plugin-ctr"
          image = "nvcr.io/nvidia/k8s-device-plugin:v0.18.0"

          env {
            name  = "FAIL_ON_INIT_ERROR"
            value = "false"
          }

          security_context {
            allow_privilege_escalation = false
            
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "device-plugin"
            mount_path = "/var/lib/kubelet/device-plugins"
          }
        }

        volume {
          name = "device-plugin"
          
          host_path {
            path = "/var/lib/kubelet/device-plugins"
          }
        }
      }
    }
  }

  depends_on = [
    azurerm_kubernetes_cluster_node_pool.node_pool,
  ]
}

resource "terraform_data" "ready_cluster" {
  depends_on = [
    azurerm_kubernetes_cluster.cluster,
    azurerm_kubernetes_cluster_node_pool.node_pool,
  ]
}
