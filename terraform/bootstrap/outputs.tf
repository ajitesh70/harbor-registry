output "state_bucket" {
  value = aws_s3_bucket.tf_state.bucket
}

output "lock_table" {
  value = aws_dynamodb_table.tf_lock.name
}

output "deploy_role_arn" {
  description = "Paste this into .github/workflows/cd.yml and ci.yml as AWS_ROLE_ARN."
  value       = aws_iam_role.deploy.arn
}

output "github_oidc_provider_arn" {
  value = local.github_oidc_provider_arn
}
