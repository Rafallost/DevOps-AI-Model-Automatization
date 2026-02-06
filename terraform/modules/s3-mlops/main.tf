# S3 Module - Two buckets: DVC data and MLflow artifacts

resource "aws_s3_bucket" "dvc_data" {
  bucket = var.dvc_bucket
  force_destroy = true  # Allow terraform destroy even if bucket contains objects

  tags = {
    Name    = var.dvc_bucket
    Project = var.project_name
    Purpose = "DVC data versioning"
  }
}

resource "aws_s3_bucket_versioning" "dvc_data" {
  bucket = aws_s3_bucket.dvc_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "dvc_data" {
  bucket = aws_s3_bucket.dvc_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "mlflow_artifacts" {
  bucket = var.mlflow_bucket
  force_destroy = true

  tags = {
    Name    = var.mlflow_bucket
    Project = var.project_name
    Purpose = "MLflow model artifacts and logs"
  }
}

resource "aws_s3_bucket_versioning" "mlflow_artifacts" {
  bucket = aws_s3_bucket.mlflow_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "mlflow_artifacts" {
  bucket = aws_s3_bucket.mlflow_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
