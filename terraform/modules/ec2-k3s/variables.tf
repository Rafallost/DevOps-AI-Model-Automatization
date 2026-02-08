variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"  # 8GB RAM - minimum for ML workloads
}

variable "subnet_id" {
  description = "Subnet ID for EC2 instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for EC2 instance"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "mlflow_bucket" {
  description = "S3 bucket name for MLflow artifacts"
  type        = string
}

variable "dvc_bucket" {
  description = "S3 bucket name for DVC data"
  type        = string
}

variable "install_monitoring" {
  description = "Install Prometheus + Grafana monitoring stack"
  type        = bool
  default     = false  # Disabled by default to save resources
}

variable "grafana_password" {
  description = "Grafana admin password"
  type        = string
  default     = "admin"
  sensitive   = true
}
