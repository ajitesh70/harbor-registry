# Registry blob + chart storage backend -- see
# helm/harbor/values-production.yaml persistence.imageChartStorage.type=s3.
# Using S3 instead of an in-cluster PVC means registry pods are stateless and
# can run >1 replica without a ReadWriteMany filesystem.

resource "aws_s3_bucket" "registry" {
  bucket = "${var.project}-registry-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "registry" {
  bucket = aws_s3_bucket.registry.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "registry" {
  bucket = aws_s3_bucket.registry.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "registry" {
  bucket                  = aws_s3_bucket.registry.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Aborts abandoned multipart uploads (common with registry blob pushes that
# get interrupted) so they don't sit around accruing storage cost forever.
resource "aws_s3_bucket_lifecycle_configuration" "registry" {
  bucket = aws_s3_bucket.registry.id
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# IRSA: the harbor-registry pod's ServiceAccount (see kubernetes.tf) assumes
# this role instead of using long-lived static AWS keys in a Harbor secret.
resource "aws_iam_role" "harbor_registry_s3" {
  name = "${var.project}-harbor-registry-s3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub" = "system:serviceaccount:${var.harbor_namespace}:harbor"
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "harbor_registry_s3" {
  name = "${var.project}-harbor-registry-s3"
  role = aws_iam_role.harbor_registry_s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BucketLevel"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.registry.arn]
      },
      {
        Sid      = "ObjectLevel"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.registry.arn}/*"]
      }
    ]
  })
}
