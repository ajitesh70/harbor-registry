# Harbor's Postgres, run externally to the cluster (RDS) rather than as the
# chart's bundled internal StatefulSet -- see helm/harbor/values-production.yaml
# database.type=external. Sits in the same public subnets as the nodes (see
# vpc.tf header comment) but publicly_accessible=false and the SG only admits
# traffic from the EKS cluster security group, so it's not internet-reachable
# despite the subnet being "public".

resource "aws_db_subnet_group" "harbor" {
  name       = "${var.project}-db"
  subnet_ids = aws_subnet.public[*].id
}

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds"
  description = "Postgres access from EKS nodes only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Postgres from EKS nodes"
    from_port       = 5432
    to_port         = 5432
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
    Name = "${var.project}-rds"
  }
}

# manage_master_user_password lets RDS generate + rotate the password in
# Secrets Manager itself -- Terraform state never holds the plaintext, and
# the CD workflow reads it at deploy time via aws_db_instance.harbor.master_user_secret.
resource "aws_db_instance" "harbor" {
  identifier     = "${var.project}-db"
  engine         = "postgres"
  engine_version = "15"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name                     = "registry"
  username                    = "harbor"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.harbor.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  multi_az                  = var.db_multi_az
  backup_retention_period   = 7
  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = !var.db_deletion_protection
  final_snapshot_identifier = var.db_deletion_protection ? "${var.project}-db-final" : null

  tags = {
    Name = "${var.project}-db"
  }
}
