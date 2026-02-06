variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
}

variable "dvc_bucket" {
  description = "S3 bucket name for DVC data (must be globally unique)"
  type        = string
}

variable "mlflow_bucket" {
  description = "S3 bucket name for MLflow artifacts (must be globally unique)"
  type        = string
}
