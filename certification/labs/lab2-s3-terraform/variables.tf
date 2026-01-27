# variables.tf
# ============================================================
# Input variables for the S3 Versioning lab
# ============================================================

variable "aws_region" {
  description = "AWS region to deploy resources"
  type = string
  default = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type = string
  default = "dev"

  validation {
    condition = contains(["dev","staging","prod"], var.environment)
    error_message = "Environment must be dev, staging or prod."
  }
}

variable "owner" {
  description = "Owner of the resources"
  type = string
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name"
  type = string
  default = "lab2-versioning"
}

# Lifecycle policy variables
variable "noncurrent_version_transitions" {
  description = "List of transition rules for noncurrent versions"
  type = list(object({
    days          = number
    storage_class = string
  }))
  default = [
    {
      days          = 30
      storage_class = "STANDARD_IA"
    },
    {
      days          = 60
      storage_class = "GLACIER"
    }
  ]
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which noncurrent versions are deleted"
  type        = number
  default     = 90
}

variable "enable_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}