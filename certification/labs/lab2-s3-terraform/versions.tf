# versions.tf
# ============================================================
# Terraform and Provider version constraints
# Best practice: Always pin versions for reproducible builds
# ============================================================

terraform {
  required_version = ">=1.0.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "lab2-s3-versioning"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}