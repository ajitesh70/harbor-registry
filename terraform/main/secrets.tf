# Harbor admin password: generated once here, stored in both Secrets Manager
# (so a human can retrieve it -- see outputs.tf) and directly as a K8s Secret
# the chart reads via existingSecretAdminPassword (see
# helm/harbor/values-production.yaml), so it's never passed as a Helm
# --set flag or committed anywhere.
#
# The DB password (RDS-managed, see rds.tf) and Redis auth token (elasticache.tf)
# don't have an existingSecret equivalent in this chart version -- the CD
# workflow fetches them from Secrets Manager at deploy time and passes them
# via masked `helm --set-string` flags instead.

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

resource "aws_secretsmanager_secret" "redis_auth" {
  name = "${var.project}/redis-auth-token"
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id     = aws_secretsmanager_secret.redis_auth.id
  secret_string = random_password.redis_auth.result
}

# The chart's redis.external.existingSecret support reads this via Helm's
# `lookup` function against the live cluster at install time (not from the
# values file), so -- unlike the DB password -- it never has to pass through
# --set/CI logs at all. Key name (REDIS_PASSWORD) is fixed by the chart.
resource "kubernetes_secret" "harbor_redis" {
  metadata {
    name      = "harbor-redis"
    namespace = kubernetes_namespace.harbor.metadata[0].name
  }

  data = {
    REDIS_PASSWORD = random_password.redis_auth.result
  }
}
