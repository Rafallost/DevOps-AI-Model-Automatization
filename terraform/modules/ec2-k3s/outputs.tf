output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.k3s.id
}

output "public_ip" {
  description = "Elastic IP address"
  value       = aws_eip.k3s.public_ip
}
