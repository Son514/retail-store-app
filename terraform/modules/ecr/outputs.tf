data "aws_caller_identity" "current" {}

output "repository_urls" {
  description = "URL of each ECR repository, keyed by repository name"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "ARN of each ECR repository, keyed by repository name"
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

output "registry_id" {
  description = "Account ID of the ECR registry"
  value       = data.aws_caller_identity.current.account_id
}
