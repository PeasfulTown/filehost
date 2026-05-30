output "s3_bucket_name" {
  value       = aws_s3_bucket.filehost_upload_bucket.id
  description = "The name of your file upload S3 Bucket."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.filehost_metadata_table.name
  description = "The name of your tracking DynamoDB table."
}

output "codeconnections_connection_arn" {
  value       = aws_codeconnections_connection.github.arn
  description = "The ARN of the GitHub connection bridge."
}
