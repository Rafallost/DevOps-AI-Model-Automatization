output "role_arn" {
  description = "ARN of GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Name of GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}
