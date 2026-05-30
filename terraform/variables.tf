variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "The target AWS Region for all resources."
}

variable "github_repo" {
  type        = string
  default     = "YOUR_GITHUB_USERNAME/YOUR_REPO_NAME" # CHANGE THIS to match your repo
  description = "The full repository path on GitHub."
}

variable "github_branch" {
  type        = string
  default     = "main"
  description = "The branch that triggers the pipeline."
}
