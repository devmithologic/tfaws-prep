# main.tf
# ============================================================
# S3 Bucket with Versioning - Infrastructure as Code
# 
# This demonstrates the answer to the assessment question:
# "How to protect sales documents against accidental deletion"
# ============================================================

# ------------------------------
# Random suffix for unique bucket name
# ------------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "main" {
  bucket = "${var.bucket_prefix}-${var.environment}-${random_id.bucket_suffix.hex}"

  force_destroy = true

    tags = {
    Name        = "${var.bucket_prefix}-${var.environment}"
    Description = "S3 bucket with versioning for document protection"
  }
}

# ------------------------------
# S3 Bucket Versioning
# This is the KEY configuration for the assessment question
# ------------------------------

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# ------------------------------
# S3 Bucket Lifecycle Configuration
# Manages costs by transitioning/expiring old versions
# ------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  depends_on = [ aws_s3_bucket_versioning.main ]

  # Rule 1: Transition and expire noncurrent versions
  rule {
    id     = "noncurrent-version-management"
    status = "Enabled"

    filter {
      prefix = "reports/"  # Only apply to reports folder
    }

    # Transition noncurrent versions to cheaper storage
    dynamic "noncurrent_version_transition" {
      for_each = var.noncurrent_version_transitions
      content {
        noncurrent_days = noncurrent_version_transition.value.days
        storage_class   = noncurrent_version_transition.value.storage_class
      }
    }

    # Delete noncurrent versions after X days
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  # Rule 2: Clean up incomplete multipart uploads
  rule {
    id     = "cleanup-incomplete-uploads"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Rule 3: Remove expired delete markers
  rule {
    id     = "cleanup-expired-delete-markers"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      expired_object_delete_marker = true
    }
  }
}

# ------------------------------
# S3 Bucket Server-Side Encryption
# Best practice: Always encrypt data at rest
# ------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# resource "aws_s3_bucket_policy" "main" {
#   bucket = aws_s3_bucket.main.id

#   # Depend on public access block to avoid conflicts
#   depends_on = [aws_s3_bucket_public_access_block.main]

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid       = "EnforceTLSRequestsOnly"
#         Effect    = "Deny"
#         Principal = "*"
#         Action    = "s3:*"
#         Resource = [
#           aws_s3_bucket.main.arn,
#           "${aws_s3_bucket.main.arn}/*"
#         ]
#         Condition = {
#           Bool = {
#             "aws:SecureTransport" = "false"
#           }
#         }
#       },
#       {
#         Sid       = "DenyIncorrectEncryptionHeader"
#         Effect    = "Deny"
#         Principal = "*"
#         Action    = "s3:PutObject"
#         Resource  = "${aws_s3_bucket.main.arn}/*"
#         Condition = {
#           StringNotEquals = {
#             "s3:x-amz-server-side-encryption" = "AES256"
#           }
#         }
#       }
#     ]
#   })
# }

# ------------------------------
# Upload sample file to test versioning
# ------------------------------
resource "aws_s3_object" "sample_report" {
  bucket       = aws_s3_bucket.main.id
  key          = "reports/sales-report.txt"
  content      = <<-EOT
    === SALES REPORT Q4 2024 ===
    Date: ${timestamp()}
    
    Total Revenue: $1,500,000
    Units Sold: 15,000
    Top Product: Widget Pro
    
    Notes: Initial version created by Terraform
    
    This file demonstrates S3 versioning.
    Each time you update this file, a new version is created.
    If you "delete" this file, S3 creates a Delete Marker.
    You can recover the file by removing the Delete Marker.
  EOT
  content_type = "text/plain"

  # Depend on versioning to ensure it's enabled first
  depends_on = [aws_s3_bucket_versioning.main]

  tags = {
    Description = "Sample sales report for versioning demo"
  }
}