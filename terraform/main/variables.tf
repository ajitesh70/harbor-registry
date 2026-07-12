variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "harbor-registry"
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "node_instance_type" {
  description = "t3.small minimum: t3.micro (1GiB) is too tight once kube-system + ~8 Harbor pods are scheduled."
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "db_instance_class" {
  description = "db.t3.micro is free-tier eligible for 12 months on a new account."
  type        = string
  default     = "db.t3.micro"
}

variable "redis_node_type" {
  description = "cache.t3.micro is free-tier eligible for 12 months on a new account."
  type        = string
  default     = "cache.t3.micro"
}

variable "harbor_namespace" {
  type    = string
  default = "harbor"
}

variable "db_multi_az" {
  description = "Standby replica in a second AZ. Off by default to stay in/near free-tier cost; flip on when this stops being a demo."
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Blocks `terraform destroy`/accidental deletion of the DB. Off by default since this is expected to be torn down and rebuilt during setup; turn on once real data lives in it."
  type        = bool
  default     = false
}

variable "deploy_role_arn" {
  description = "ARN of the github-actions-harbor-registry-deploy role from terraform/bootstrap — granted an EKS access entry so CI can kubectl/helm against this cluster."
  type        = string
}
