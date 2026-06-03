# 1. Create DynamoDB Table to store file metadata
resource "aws_dynamodb_table" "filehost_metadata_table" {
  name         = "FileMetadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "FileName"

  attribute {
    name = "FileName"
    type = "S"
  }

  # Block for financial protection: Circuit breaker which will throttle table if
  # an infinite loop tries to spike the requests
  on_demand_throughput {
    max_read_request_units  = 4
    max_write_request_units = 4
  }
}

# 2. Create S3 Bucket where files are uploaded
resource "aws_s3_bucket" "filehost_upload_bucket" {
  bucket = format(
    "filehost-uploads-%s-%s-an",
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.region
  )
  bucket_namespace = "account-regional"
  force_destroy    = true
}

# ============================================================
# METADATA EXTRACTOR LAMBDA
# ============================================================
# 3. Create IAM execution Role for the Lambda Function
resource "aws_iam_role" "filehost_extractor_lambda_role" {
  name = "metadata_extractor_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Attach permissions to the Lambda role so it can read from S3 and write to DynamoDB
resource "aws_iam_role_policy" "filehost_extractor_lambda_policy" {
  role = aws_iam_role.filehost_extractor_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:HeadObject"]
        Resource = "${aws_s3_bucket.filehost_upload_bucket.arn}/uploads/*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.filehost_metadata_table.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# 4. Automate zipping the Lambda python file before uploading
data "archive_file" "filehost_extractor_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/extractor.py"
  output_path = "${path.module}/../lambda/extractor.zip"
}

# 5. Create the Lambda Function itself
resource "aws_lambda_function" "filehost_extractor_lambda" {
  filename         = data.archive_file.filehost_extractor_lambda_zip.output_path
  function_name    = "filehost-extractor-lambda"
  role             = aws_iam_role.filehost_extractor_lambda_role.arn
  handler          = "extractor.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.filehost_extractor_lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.filehost_metadata_table.name
    }
  }
}

# 6. Authorize S3 to execute the Lambda function
resource "aws_lambda_permission" "filehost_allow_s3_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.filehost_extractor_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.filehost_upload_bucket.arn
}

# 7. Tell S3 to alert Lambda whenever a new object is created
resource "aws_s3_bucket_notification" "filehost_bucket_notification" {
  bucket = aws_s3_bucket.filehost_upload_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.filehost_extractor_lambda.arn
    events              = ["s3:ObjectCreated:*"]

    filter_prefix = "uploads/"
  }

  depends_on = [aws_lambda_permission.filehost_allow_s3_invoke_lambda]
}

# ============================================================
# SERVER LAMBDA
# ============================================================
resource "aws_iam_role" "filehost_server_lambda_role" {
  name = "filehost_server_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "filehost_server_lambda_policy" {
  role = aws_iam_role.filehost_server_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.filehost_upload_bucket.arn}/uploads/*"
      },
      {
        Effect = "Allow"
        Action = ["dynamodb:GetItem"]
        Resource = "${aws_dynamodb_table.filehost_metadata_table.arn}"
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

data "archive_file" "filehost_server_lambda_zip" {
  type = "zip"
  source_dir = "${path.module}/../app/lambda_dist"
  output_path = "${path.module}/../app/lambda_deployment.zip"
}

resource "aws_lambda_function" "filehost_server_lambda" {
  filename = data.archive_file.filehost_server_lambda_zip.output_path
  function_name = "filehost-server-lambda"
  role = aws_iam_role.filehost_server_lambda_role.arn
  handler = "server.handler"
  runtime = "python3.12"
  source_code_hash = data.archive_file.filehost_server_lambda_zip.output_base64sha256

  environment {
    variables = {
      UPLOAD_BUCKET_NAME = aws_s3_bucket.filehost_upload_bucket.bucket
      METADATA_TABLE_NAME = aws_dynamodb_table.filehost_metadata_table.name
    }
  }
}

# ============================================================
# API GATEWAY
# ============================================================
# Create HTTP API Gateway
resource "aws_apigatewayv2_api" "filehost_api" {
  name = "filehost-server-api"
  protocol_type = "HTTP"
}

# Points API Gateway to existing Lambda function
resource "aws_apigatewayv2_integration" "filehost_server_lambda_integration" {
  api_id = aws_apigatewayv2_api.filehost_api.id
  integration_type = "AWS_PROXY"
  integration_uri = aws_lambda_function.filehost_server_lambda.arn
  payload_format_version = "2.0"
}

# Create catch all route ($default routes all paths and methods)
resource "aws_apigatewayv2_route" "filehost_gateway" {
  api_id = aws_apigatewayv2_api.filehost_api.id
  route_key = "ANY /{proxy+}"
  target = "integrations/${aws_apigatewayv2_integration.filehost_server_lambda_integration.id}"
}

# Deploy API to live Stage named '$default' (creates public URL)
resource "aws_apigatewayv2_stage" "filehost_default_stage" {
  api_id = aws_apigatewayv2_api.filehost_api.id
  name = "$default"
  auto_deploy = true
}

# Give API Gateway permission to invoke Lambda function
resource "aws_lambda_permission" "filehost_apigateway_lambda_permission" {
  statement_id = "AllowAPIGatewayInvoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.filehost_server_lambda.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.filehost_api.execution_arn}/*/*"
}
