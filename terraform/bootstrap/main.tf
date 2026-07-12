# One-time bootstrap, run manually with your own AWS credentials:
#
#   terraform -chdir=terraform/bootstrap init
#   terraform -chdir=terraform/bootstrap apply -var="github_repo=<your-gh-user>/harbor-registry"
#
# Creates the Terraform state backend (S3 + DynamoDB lock table) and the
# GitHub Actions OIDC deploy role that terraform/main and .github/workflows/cd.yml
# assume for everything after this. Nothing here is applied by CI — it has to
# exist before CI can authenticate at all.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

# --- Terraform state backend for terraform/main ---

resource "aws_s3_bucket" "tf_state" {
  bucket = "harbor-registry-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "harbor-registry-tf-lock"
  billing_mode = "PAY_PER_REQUEST" # no idle cost, free-tier friendly
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# --- GitHub Actions OIDC federation ---
#
# If this AWS account already has a token.actions.githubusercontent.com OIDC
# provider (e.g. left over from another project), set create_github_oidc_provider=false
# and it'll be looked up instead of recreated (an account can only have one).

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_github_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# --- Deploy role assumed by .github/workflows/{ci,cd}.yml ---

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "github-actions-harbor-registry-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

# Deliberately service-level (not resource-scoped) permissions: this role IS
# Terraform for this stack, so it needs to create/read/destroy EC2 (VPC/SG),
# EKS, RDS, ElastiCache, S3, Secrets Manager, and IAM roles/policies for the
# cluster + IRSA. It's scoped to these services only, not account-admin — but
# within each service it's broad. Tighten with resource-level conditions once
# the resource set stabilizes; not worth hand-rolling now and risking a
# mid-apply permissions gap that leaves partial infra behind.
data "aws_iam_policy_document" "deploy_permissions" {
  statement {
    sid    = "InfraServices"
    effect = "Allow"
    actions = [
      "ec2:*",
      "eks:*",
      "rds:*",
      "elasticache:*",
      "s3:*",
      "secretsmanager:*",
      "logs:*",
      "kms:*",
    ]
    resources = ["*"]
  }

  # ElastiCache (and other AWS services) rely on a service-linked role that
  # AWS normally auto-creates on first use -- but that creation itself is an
  # iam: action, so it has to be explicitly granted rather than assumed.
  statement {
    sid    = "ServiceLinkedRolesForInfraServices"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "elasticache.amazonaws.com",
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "rds.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "TfStateAccess"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.tf_state.arn, "${aws_s3_bucket.tf_state.arn}/*"]
  }

  statement {
    sid       = "TfLockAccess"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = [aws_dynamodb_table.tf_lock.arn]
  }

  # IAM is scoped by name prefix so this role can't touch unrelated roles/policies/users.
  statement {
    sid    = "IamForThisProjectOnly"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
      "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:ListPolicyVersions",
      "iam:CreateOpenIDConnectProvider", "iam:GetOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/harbor-registry-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/harbor-registry-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/*",
    ]
  }

  statement {
    sid       = "ReadOnlyAccountInfo"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity", "iam:ListOpenIDConnectProviders"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy_permissions" {
  name   = "harbor-registry-deploy-permissions"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy_permissions.json
}
