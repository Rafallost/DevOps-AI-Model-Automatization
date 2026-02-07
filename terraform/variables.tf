variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "wms"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "availability_zone" {
  description = "Availability zone for subnet"
  type        = string
  default     = "eu-central-1a"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"  # 8GB RAM, stable for ML workloads with PyTorch
}

variable "my_ip" {
  description = "Your IP address with /32 suffix (e.g., 1.2.3.4/32)"
  type        = string
}

variable "key_name" {
  description = "Name of existing EC2 key pair"
  type        = string
}

variable "dvc_bucket" {
  description = "S3 bucket name for DVC data (must be globally unique - append account ID)"
  type        = string
}

variable "mlflow_bucket" {
  description = "S3 bucket name for MLflow artifacts (must be globally unique - append account ID)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo'"
  type        = string
  default     = "Rafallost/Water-Meters-Segmentation-Autimatization"
}
