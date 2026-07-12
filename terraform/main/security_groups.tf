# Node security group is created by EKS itself (the "cluster security group",
# shared by control plane + nodes). We only add the extra rules EKS doesn't
# create automatically: inbound for Harbor's exposed Service, and inbound
# from that same SG for RDS/ElastiCache (defined in rds.tf/elasticache.tf).
#
# Harbor is exposed via expose.type=loadBalancer (see
# helm/harbor/values.yaml), an AWS NLB with target-type=instance that Kubernetes
# provisions and manages itself. Kubernetes/AWS pick the backing NodePort
# dynamically from the standard 30000-32767 range rather than a fixed port,
# so (per standard EKS reference architecture) this SG opens that whole range
# instead of a single port -- only traffic actually routed by kube-proxy to a
# real Service reaches anything, so this isn't as broad as it looks.

resource "aws_security_group" "harbor_ingress" {
  name        = "${var.project}-harbor-ingress"
  description = "Allows the Harbor NLB to reach its NodePort on cluster nodes"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "NodePort range from internet via NLB (target-type=instance)"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-harbor-ingress"
  }
}
