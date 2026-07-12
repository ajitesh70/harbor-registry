# Harbor's Redis (job queue + core cache), run externally via ElastiCache --
# see helm/harbor/values-production.yaml redis.type=external. A replication
# group (not the plain aws_elasticache_cluster resource) so we get
# transit/at-rest encryption and an auth token, while still running a single
# cache.t3.micro node (num_cache_clusters=1) to keep cost down.

resource "aws_elasticache_subnet_group" "harbor" {
  name       = "${var.project}-redis"
  subnet_ids = aws_subnet.public[*].id
}

resource "aws_security_group" "redis" {
  name        = "${var.project}-redis"
  description = "Redis access from EKS nodes only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Redis from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-redis"
  }
}

resource "random_password" "redis_auth" {
  length  = 32
  special = false # ElastiCache AUTH tokens can't contain some special chars
}

resource "aws_elasticache_replication_group" "harbor" {
  replication_group_id = "${var.project}-redis"
  description          = "Harbor core/jobservice cache + job queue"

  engine             = "redis"
  engine_version     = "7.1"
  node_type          = var.redis_node_type
  num_cache_clusters = 1
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.harbor.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth.result

  automatic_failover_enabled = false # single node; would need num_cache_clusters >= 2

  tags = {
    Name = "${var.project}-redis"
  }
}
