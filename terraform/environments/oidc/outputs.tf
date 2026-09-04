output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "deploy_role_arn" {
  description = "ARN of the GitHub Actions deploy role (to assume in workflows)"
  value       = aws_iam_role.github_actions_deploy.arn
}

output "deploy_role_name" {
  description = "Name of the GitHub Actions deploy role"
  value       = aws_iam_role.github_actions_deploy.name
}
