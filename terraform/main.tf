terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  availability_zone  = var.availability_zone
  my_ip              = var.my_ip
}

# S3 Buckets Module
module "s3" {
  source = "./modules/s3-mlops"

  project_name  = var.project_name
  dvc_bucket    = var.dvc_bucket
  mlflow_bucket = var.mlflow_bucket
}

# ECR Module
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
}

# IAM + OIDC Module - DISABLED for AWS Academy Learner Lab
# Learner Lab does not allow creating IAM roles or OIDC providers
# GitHub Actions will use environment credentials instead
# module "iam_github" {
#   source = "./modules/iam-github-oidc"
#
#   project_name       = var.project_name
#   github_repo        = var.github_repo
#   dvc_bucket_arn     = module.s3.dvc_bucket_arn
#   mlflow_bucket_arn  = module.s3.mlflow_bucket_arn
#   ecr_repository_arn = module.ecr.repository_arn
# }

# EC2 + k3s Module
module "ec2" {
  source = "./modules/ec2-k3s"

  project_name      = var.project_name
  instance_type     = var.instance_type
  subnet_id         = module.vpc.public_subnet_id
  security_group_id = module.vpc.security_group_id
  key_name          = var.key_name
  mlflow_bucket     = var.mlflow_bucket
  dvc_bucket        = var.dvc_bucket

  # Monitoring stack (optional)
  install_monitoring = var.install_monitoring
  grafana_password   = var.grafana_password
}
