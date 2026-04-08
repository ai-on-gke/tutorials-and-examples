locals {
  registry_extra_info = var.registry_extra_info
  #registry_service_account_annotations = var.registry_extra_service_account_annotations
  #registry_pod_labels = var.registry_extra_pod_labels
  #registry_pod_env_vars = var.registry_extra_pod_env_vars

  registry_service_account_info = var.k3s_service_accounts["image-registry-helpers"]
}

resource "docker_image" "images" {
  for_each = var.images_to_build
  name = each.value.full_name
  platform = each.value.platform
  build {
    context    = each.value.build_context
    dockerfile = "${each.value.build_context}/Dockerfile"
    builder    = "default"
    platform = each.value.platform
  }
  force_remove = true

  # rebuild image only when its source has changed 
  triggers = {
    dir_sha1 = sha1(join(
      "", 
      [
        for f in fileset(each.value.build_context, "./**") : 
        filesha1("${each.value.build_context}/${f}")
      ]
    ))
  }
}

resource "docker_registry_image" "registry_images" {
  for_each = docker_image.images
  #auth_config {
  #  address  = var.registry_uri
  #  username = var.registry_username
  #  password = var.registry_password
  #}
  name = each.value.name
  keep_remotely = false
  lifecycle {
    replace_triggered_by = [
      docker_image.images[each.key]
    ]
  }
}

resource "kubernetes_service_account_v1" "image_registry_sa" {
  metadata {
    name = local.registry_service_account_info.name
    namespace = local.registry_service_account_info.namespace
    annotations = merge(
      {},
      var.registry_extra_info.service_account_annotations
    )
  }
  depends_on = [
    kubernetes_namespace_v1.namespaces
  ]
}

resource "kubernetes_job_v1" "public_image_downloader" {
  count =1
  metadata {
    name      = "image-downloader"
    namespace = local.registry_service_account_info.namespace
    
    labels = {
      app = "public-image-downloader"
    }
  }

  spec {
    backoff_limit = 4
    
    template {
      metadata {
        labels = merge(
          {
            app = "public-image-downloader"
          },
          var.registry_extra_info.pod_labels,
        )
      }

      spec {
        service_account_name = kubernetes_service_account_v1.image_registry_sa.metadata[0].name
        container {
          name    = "image-downloader"
          image       = docker_registry_image.registry_images["helper"].name
          image_pull_policy = "Always"
          command = [
            "bash",
            "-c",
            <<EOF
            set -e
            
            /venv/bin/python3 /helper/main.py \
              --cloud-provider-type "${var.cloud_provider}" \
              copy_public_images \
              --images '${jsonencode([for img in var.public_images_to_pull: {"src" = img.source_full_name, "dest" = img.full_name} ])}'

            EOF
          ]
          
          dynamic "env" {
            for_each = var.registry_extra_info.pod_environment_variables
            content {
              name = env.key
              value = env.value
            }
          }
          resources {
            limits = {
              cpu    = "500m"
              memory = "500Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "250Mi"
            }
          }
        }

        restart_policy = "Never"
      }
    }
  }
  timeouts {
    create = "20m"
    update = "20m"
  }
  wait_for_completion=true
  lifecycle {
    replace_triggered_by = [
      docker_registry_image.registry_images["helper"],
    ]
  }
}


resource "kubernetes_daemon_set_v1" "image_puller" {
  #for_each = toset(var.registry_extra_info.image_puller_runtime_classes)
  metadata {
    #name      = "image-puller-${each.key}"
    name      = "image-puller"
    namespace = local.registry_service_account_info.namespace
  }

  spec {
    selector {
      match_labels = {
        app = "image-puller"
      }
    }

    template {
      metadata {
        labels = merge(
          {
            app = "image-puller"
          },
          var.registry_extra_info.pod_labels,
        )
      }

      spec {
        #runtime_class_name = each.key
        service_account_name = kubernetes_service_account_v1.image_registry_sa.metadata[0].name
        init_container {
          name              = "image-puller"
          image       = docker_registry_image.registry_images["helper"].name
          image_pull_policy = "Always"

          command = [
            "/bin/sh",
            "-c",
            <<EOF
            /venv/bin/python3 /helper/main.py \
              --cloud-provider-type "${var.cloud_provider}" \
              pull_images \
              --images '${join(",", concat(values(var.images_to_build)[*].full_name, values(var.public_images_to_pull)[*].full_name))}'

            EOF
          ]
          
          dynamic "env" {
            for_each = var.registry_extra_info.pod_environment_variables
            content {
              name = env.key
              value = env.value
            }
          }


          volume_mount {
            name       = "containerd-sock"
            mount_path = "/run/containerd/containerd.sock"
          }
        }

        container {
          name              = "sleeper"
          image       = docker_registry_image.registry_images["helper"].name
          image_pull_policy = "Always"
          command           = ["/bin/sh", "-c", "sleep infinity"]
        }

        volume {
          name = "containerd-sock"
          host_path {
            path = "/run/containerd/containerd.sock"
            type = "Socket"
          }
        }
        
        toleration {
          operator = "Exists"
        }

      }
    }
  }
  timeouts {
    create = "20m"
    update = "20m"
  }
  wait_for_rollout = true
  lifecycle {
    replace_triggered_by = [
      docker_registry_image.registry_images,
      kubernetes_job_v1.public_image_downloader,
    ]
  }
}
