variable "region" {
  type    = string
  default = "us-east-1"
}

variable "github_repo" {
  description = "GitHub \"org/repo\" allowed to assume the deploy role via OIDC, e.g. \"yourname/harbor-registry\"."
  type        = string
}

variable "create_github_oidc_provider" {
  description = "False if token.actions.githubusercontent.com OIDC provider already exists in this AWS account (an account may only have one)."
  type        = bool
  default     = true
}
