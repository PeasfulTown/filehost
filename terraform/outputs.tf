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

output "apigateway_url" {
  value = aws_apigatewayv2_stage.filehost_default_stage.invoke_url
  description = "API Gateway URL"
}

output "cloudfront_url" {
  value = aws_cloudfront_distribution.filehost_cloudfront.domain_name
  description = "Live public HTTP URL of the application"
}
