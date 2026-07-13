output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "region" {
  value = var.region
}

output "registry_bucket" {
  value = aws_s3_bucket.registry.bucket
}

output "db_endpoint" {
  value = aws_db_instance.harbor.address
}

output "db_secret_arn" {
  description = "RDS-managed Secrets Manager ARN holding the Postgres master password."
  value       = aws_db_instance.harbor.master_user_secret[0].secret_arn
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.harbor.primary_endpoint_address
}

output "harbor_admin_secret_arn" {
  description = "Secrets Manager ARN holding the Harbor admin password (also in-cluster as the harbor-admin-password Secret)."
  value       = aws_secretsmanager_secret.harbor_admin.arn
}

output "harbor_registry_s3_role_arn" {
  value = aws_iam_role.harbor_registry_s3.arn
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name}"
}
