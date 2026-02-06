output "dvc_bucket_name" {
  description = "DVC data bucket name"
  value       = aws_s3_bucket.dvc_data.id
}

output "dvc_bucket_arn" {
  description = "DVC data bucket ARN"
  value       = aws_s3_bucket.dvc_data.arn
}

output "mlflow_bucket_name" {
  description = "MLflow artifacts bucket name"
  value       = aws_s3_bucket.mlflow_artifacts.id
}

output "mlflow_bucket_arn" {
  description = "MLflow artifacts bucket ARN"
  value       = aws_s3_bucket.mlflow_artifacts.arn
}
