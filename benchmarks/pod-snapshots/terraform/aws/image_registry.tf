resource "aws_ecr_repository" "repositories" {
  for_each = merge(module.common_info.images_to_build, module.common_info.public_images_to_pull)
  name                 = each.value.repository
  image_tag_mutability = "MUTABLE"
  force_delete = true
}

data "aws_iam_policy_document" "registry_pod_identity_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}


resource "aws_iam_role" "registry_ecr_role" {
  name               = "${var.name_prefix}-registry-pod-identity-role"
  assume_role_policy = data.aws_iam_policy_document.registry_pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "registry_ecr_policy_attachment" {
  role       = aws_iam_role.registry_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_eks_pod_identity_association" "ecr_pod_identity" {
  for_each = { for sa in ["image-registry-helpers"]: sa=>module.common_info.k3s_service_accounts[sa] }
  cluster_name = aws_eks_cluster.cluster.name
  namespace = each.value.namespace
  service_account = each.value.name
  role_arn        = aws_iam_role.registry_ecr_role.arn
  depends_on = [
    aws_iam_role_policy_attachment.registry_ecr_policy_attachment,
  ]
}



