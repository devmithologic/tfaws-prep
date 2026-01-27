# outputs.tf
# ============================================================
# Output values for reference and scripting
# ============================================================

output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.main.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.main.arn
}

output "bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.main.region
}

output "versioning_status" {
  description = "Versioning status of the bucket"
  value       = aws_s3_bucket_versioning.main.versioning_configuration[0].status
}

output "sample_file_key" {
  description = "Key of the sample file uploaded"
  value       = aws_s3_object.sample_report.key
}

output "sample_file_version_id" {
  description = "Version ID of the sample file"
  value       = aws_s3_object.sample_report.version_id
}

# Useful commands output
output "useful_commands" {
  description = "Helpful AWS CLI commands for testing"
  value       = <<-EOT
    
    # List all versions of the sample file:
    aws s3api list-object-versions --bucket ${aws_s3_bucket.main.id} --prefix reports/sales-report.txt
    
    # Download current version:
    aws s3 cp s3://${aws_s3_bucket.main.id}/reports/sales-report.txt ./current.txt
    
    # "Delete" the file (creates Delete Marker):
    aws s3 rm s3://${aws_s3_bucket.main.id}/reports/sales-report.txt
    
    # View Delete Markers:
    aws s3api list-object-versions --bucket ${aws_s3_bucket.main.id} --query 'DeleteMarkers'
    
  EOT
}