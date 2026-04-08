resource "aws_eks_cluster" "cluster" {
  name = local.cluster_name

  access_config {
    authentication_mode = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true

    subnet_ids = [
      aws_subnet.subnet_az1.id,
      aws_subnet.subnet_az2.id,
    ]
  }

  depends_on = [
    aws_route.internet_access,
    aws_internet_gateway.igw,
  ]
}

resource "aws_iam_role" "cluster" {
  name = "${var.default_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

data "cloudinit_config" "eks_devmapper_node_init" {
  gzip          = false
  base64_encode = true

  part {
      content_type = "text/x-shellscript"
      content      = file("${path.module}/files/init-devmapper.sh")
    }
}

resource "aws_launch_template" "node_pool_template" {
  for_each = var.node_pools
  name_prefix   = "${var.default_name}-${each.key}"
  update_default_version = true

  user_data = each.value.setup_devmapper_pool? data.cloudinit_config.eks_devmapper_node_init.rendered: null

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 100
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.default_name}-${each.key}-node-template"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "node_pool" {
  for_each = var.node_pools
  node_group_name       = "${var.default_name}-${each.key}"
  cluster_name    = aws_eks_cluster.cluster.name
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = [
      aws_subnet.subnet_az1.id,
      aws_subnet.subnet_az2.id,
  ]

  ami_type = each.value.gpu_enabled ? "AL2023_x86_64_NVIDIA" : (each.value.arm_enabled ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD")

  launch_template {
    name    = aws_launch_template.node_pool_template[each.key].name
    version = aws_launch_template.node_pool_template[each.key].latest_version
  }

  instance_types = [each.value.machine_type]

  labels = each.value.labels

  scaling_config {
    desired_size = each.value.min_count
    max_size = each.value.max_count
    min_size = each.value.min_count
  }
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_policy
  ]
}

resource "aws_iam_role" "eks_node_group_role" {
  name = "${var.default_name}-cluster-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "helm_release" "kata-deploy" {
  name      = "kata-deploy"
  chart     = "oci://ghcr.io/kata-containers/kata-deploy-charts/kata-deploy"
  create_namespace = true
  namespace = "kata-containers"
  version = "3.26.0"

  values = [
    yamlencode({
      nodeSelector = {
        "benchmarking-sandbox-pool" = "true"
      },
     shims = {
      disableAll = true,
      qemu = { enabled = true},
      qemu-cca = { enabled = true},
      fc = { enabled = true, snappshotter = "devmapper" }}
    }), 
  ]

  depends_on = [
    aws_eks_node_group.node_pool
  ]
}
