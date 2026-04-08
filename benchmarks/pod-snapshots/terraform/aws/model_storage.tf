resource "aws_s3_bucket" "bucket" {
  bucket = var.name_prefix
  force_destroy = true
}

resource "aws_iam_role" "model_storage_pod_identity_role" {
  name = "EKSPodIdentityS3Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_access_attach" {
  role       = aws_iam_role.model_storage_pod_identity_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_eks_pod_identity_association" "model_downloader_s3_pod_identity" {
  for_each = { for sa in ["model-storage-helpers", "runai_vllm_test"]: sa=>module.common_info.k3s_service_accounts[sa] }
  cluster_name = aws_eks_cluster.cluster.name
  namespace =     each.value.namespace
  service_account = each.value.name
  role_arn        = aws_iam_role.model_storage_pod_identity_role.arn
}
