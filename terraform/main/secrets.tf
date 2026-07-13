# Harbor admin password: generated once here, stored in both Secrets Manager
# (so a human can retrieve it -- see outputs.tf) and directly as a K8s Secret
# the chart reads via existingSecretAdminPassword (see
# helm/harbor/values-production.yaml), so it's never passed as a Helm
# --set flag or committed anywhere.
#
# The DB password (RDS-managed, see rds.tf) doesn't have an existingSecret
# equivalent in this chart version -- the CD workflow fetches it from Secrets
# Manager at deploy time and passes it via a masked `helm --set-string` flag
# instead. (Redis has no password at all -- see elasticache.tf for why.)

resource "random_password" "harbor_admin" {
  length  = 24
  special = true
}

resource "aws_secretsmanager_secret" "harbor_admin" {
  name = "${var.project}/harbor-admin-password"
}

resource "aws_secretsmanager_secret_version" "harbor_admin" {
  secret_id     = aws_secretsmanager_secret.harbor_admin.id
  secret_string = random_password.harbor_admin.result
}

resource "kubernetes_secret" "harbor_admin" {
  metadata {
    name      = "harbor-admin-password"
    namespace = kubernetes_namespace.harbor.metadata[0].name
  }

  data = {
    HARBOR_ADMIN_PASSWORD = random_password.harbor_admin.result
  }
}

# Convenience pointer to the RDS-managed secret so the CD workflow doesn't
# have to know the ARN construction -- see outputs.tf db_secret_arn.
data "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_db_instance.harbor.master_user_secret[0].secret_arn
}
