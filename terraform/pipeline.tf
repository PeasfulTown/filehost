resource "aws_codeconnections_connection" "github" {
  name          = var.github_connection_name
  provider_type = "GitHub"
}

# --- S3 Bucket to Store Pipeline Artifacts ---
resource "aws_s3_bucket" "filehost_pipeline_bucket" {
  bucket    = format(
    "filehost-pipeline-artifacts-%s-%s-an",
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.region
  )
  bucket_namespace = "account-regional"
  force_destroy    = true
}

# --- IAM Role for CodePipeline ---
resource "aws_iam_role" "filehost_codepipeline_role" {
  name = "filehost-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
    }]
  })
}

# CodePipeline policy to allow reading/writing to its artifact bucket and invoking CodeBuild
resource "aws_iam_role_policy" "filehost_codepipeline_policy" {
  name = "filehost-codepipeline-policy"
  role = aws_iam_role.filehost_codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketVersioning", "s3:PutObjectAcl", "s3:PutObject"]
        Resource = ["${aws_s3_bucket.filehost_pipeline_bucket.arn}", "${aws_s3_bucket.filehost_pipeline_bucket.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection"]
        Resource = [aws_codeconnections_connection.github.arn]
      }
    ]
  })
}

# --- IAM Role for CodeBuild ---
resource "aws_iam_role" "filehost_codebuild_role" {
  name = "filehost-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })
}

# Give CodeBuild admin/broad rights for this practice run so it can provision S3, Lambda, and DynamoDB
resource "aws_iam_role_policy" "filehost_codebuild_policy" {
  name = "filehost_codebuild_policy"
  role = aws_iam_role.filehost_codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["*"]
        Resource = "*"
      }
    ]
  })
}

# --- CodeBuild Project 1: Testing (CI) ---
resource "aws_codebuild_project" "test_project" {
  name          = "filehost-project-test"
  service_role  = aws_iam_role.filehost_codebuild_role.arn
  build_timeout = "5"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec_test.yml"
  }
}

# --- CodeBuild Project 2: Deployment (CD) ---
resource "aws_codebuild_project" "deploy_project" {
  name          = "filehost-project-deployment"
  service_role  = aws_iam_role.filehost_codebuild_role.arn
  build_timeout = "10"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name = "BACKEND_BUCKET_NAME"
      value = "terraform-state-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec_deploy.yml"
  }

}

# --- The CodePipeline Definition ---
resource "aws_codepipeline" "pipeline" {
  name     = "python-infra-pipeline"
  role_arn = aws_iam_role.filehost_codepipeline_role.arn

  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.filehost_pipeline_bucket.bucket
    type     = "S3"
  }

  # Triggers on pull requests
  trigger {
    provider_type = "CodeStarSourceConnection"

    git_configuration {
      source_action_name = "SourceAction"

      pull_request {
        events = ["OPEN", "UPDATED"]

        branches {
          includes = ["main"]
        }
      }

      push {
        branches {
          includes = ["main"]
        }
      }
    }
  }

  # STAGE 1: Source (linked to GitHub repository)
  stage {
    name = "Source"

    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codeconnections_connection.github.arn
        FullRepositoryId = var.github_repo
        BranchName       = "main"
      }
    }
  }

  # STAGE 2: CI (Run Unit Tests)
  stage {
    name = "Test"

    action {
      name             = "RunTests"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["test_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.test_project.name
      }
    }
  }

  # STAGE 3: CD (Terraform Apply)
  stage {
    name = "Deploy"

    # Don't run the deploy stage if pipeline was triggered by Pull Request event
    before_entry {
      condition {
        result = "SKIP"
        rule {
          name = "SkipOnPullRequest"
          rule_type_id {
            category = "Rule"
            provider = "VariableCheck"
            owner = "AWS"
            version = "1"
          }
          configuration = {
            Variable = "#{SourceVariables.PullRequestId}"
            Value = "[0-9]+"
            Operator = "MATCHES"
          }
        }
      }

    }

    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.deploy_project.name
      }
    }
  }
}
