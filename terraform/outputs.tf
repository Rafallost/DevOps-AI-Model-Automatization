output "ec2_instance_id" {
  description = "EC2 instance ID (use for start/stop commands)"
  value       = module.ec2.instance_id
}

output "ec2_public_ip" {
  description = "EC2 Elastic IP address"
  value       = module.ec2.public_ip
}

output "mlflow_url" {
  description = "MLflow tracking server URL"
  value       = "http://${module.ec2.public_ip}:5000"
}

output "ecr_repository_url" {
  description = "ECR repository URL for docker push"
  value       = module.ecr.repository_url
}

output "ssh_command" {
  description = "SSH command to connect to EC2"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${module.ec2.public_ip}"
}

output "dvc_bucket" {
  description = "DVC data bucket name"
  value       = module.s3.dvc_bucket_name
}

output "mlflow_bucket" {
  description = "MLflow artifacts bucket name"
  value       = module.s3.mlflow_bucket_name
}
