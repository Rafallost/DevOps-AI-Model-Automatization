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

output "monitoring_enabled" {
  description = "Whether Prometheus + Grafana monitoring is enabled"
  value       = var.install_monitoring
}

output "grafana_port_forward" {
  description = "Command to access Grafana (run on EC2 via SSH)"
  value       = var.install_monitoring ? "kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80" : "Monitoring not enabled"
}

output "prometheus_port_forward" {
  description = "Command to access Prometheus (run on EC2 via SSH)"
  value       = var.install_monitoring ? "kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090" : "Monitoring not enabled"
}

output "ssh_tunnel_grafana" {
  description = "SSH tunnel command for Grafana access"
  value       = var.install_monitoring ? "ssh -i ~/.ssh/${var.key_name}.pem -L 3000:localhost:3000 ec2-user@${module.ec2.public_ip}" : "Monitoring not enabled"
}
