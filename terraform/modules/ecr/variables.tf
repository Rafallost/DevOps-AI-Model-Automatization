variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
}

variable "repository_name" {
  description = "ECR repository name"
  type        = string
  default     = "wms-model"
}
