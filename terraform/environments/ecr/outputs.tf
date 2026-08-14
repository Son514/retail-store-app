output "repository_urls" {
  description = "URL of each ECR repository, keyed by repository name"
  value       = module.ecr.repository_urls
}

output "repository_arns" {
  description = "ARN of each ECR repository, keyed by repository name"
  value       = module.ecr.repository_arns
}

output "registry_id" {
  description = "Account ID of the ECR registry"
  value       = module.ecr.registry_id
}
