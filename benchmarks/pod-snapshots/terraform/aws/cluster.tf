resource "aws_iam_role" "cluster" {
  name = "${var.name_prefix}-cluster-role"
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

resource "aws_iam_role" "eks_node_group_role" {
  name = "${var.name_prefix}-cluster-node-group-role"

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

resource "aws_eks_cluster" "cluster" {
  name = var.name_prefix
  region = var.region

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
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
  ]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.cluster.name
  addon_name   = "eks-pod-identity-agent"
}



resource "aws_eks_node_group" "node_pool" {
  for_each = var.node_pools
  node_group_name       = "${var.name_prefix}-${each.key}"
  cluster_name    = aws_eks_cluster.cluster.name
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = [
      aws_subnet.subnet_az1.id,
      aws_subnet.subnet_az2.id,
  ]

  ami_type = each.value.gpu_enabled ? "AL2023_x86_64_NVIDIA" : "AL2023_x86_64_STANDARD"

  instance_types = [each.value.machine_type]
  disk_size="100"

  labels = each.value.labels
  scaling_config {
    desired_size = each.value.min_count
    max_size = each.value.max_count
    min_size = each.value.min_count
  }
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_policy,
  ]
}


resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  namespace  = "nvidia"
  create_namespace=true
  version = "0.18.2" 
  wait = true

  set = [
    {
      name="gfd.enabled"
      value="true"
    },
  ]
  depends_on = [
    aws_eks_node_group.node_pool
  ]
}

resource "terraform_data" "ready_cluster" {
    depends_on = [
      aws_eks_cluster.cluster,
      aws_eks_node_group.node_pool,
    ]
}
