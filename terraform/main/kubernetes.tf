# Namespace + the one ServiceAccount all Harbor components run as (the chart
# has a single top-level serviceAccountName, not one per component -- see
# s3.tf for why that SA needs an IAM role attached).

resource "kubernetes_namespace" "harbor" {
  metadata {
    name = var.harbor_namespace
  }

  depends_on = [aws_eks_node_group.default]
}

resource "kubernetes_service_account" "harbor" {
  metadata {
    name      = "harbor"
    namespace = kubernetes_namespace.harbor.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.harbor_registry_s3.arn
    }
  }
}
