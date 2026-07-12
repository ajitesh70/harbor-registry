terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }

  # Bucket/table created by terraform/bootstrap. Account ID is hardcoded here
  # (backend blocks can't reference variables/data sources) — same AWS account
  # (708325791586) used by the gitactions/spring-demo project.
  backend "s3" {
    bucket         = "harbor-registry-tfstate-708325791586"
    key            = "env/main/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "harbor-registry-tf-lock"
    encrypt        = true
  }
}
