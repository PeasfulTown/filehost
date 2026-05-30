terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket = "terraform-state-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"
    key    = "filehost/terraform.tfstate"
    region = "us-east-1"
  }
  
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
