variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo'"
  type        = string
}

variable "dvc_bucket_arn" {
  description = "ARN of DVC S3 bucket"
  type        = string
}

variable "mlflow_bucket_arn" {
  description = "ARN of MLflow S3 bucket"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of ECR repository"
  type        = string
}
