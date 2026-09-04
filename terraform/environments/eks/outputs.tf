output "cluster_id" {
  description = "ID of the EKS cluster"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Certificate authority data of the EKS cluster (base64)"
  value       = module.eks.cluster_certificate_authority_data
}

output "node_group_arn" {
  description = "ARN of the managed node group"
  value       = module.eks.node_group_arn
}

output "node_security_group_id" {
  description = "ID of the node security group"
  value       = module.eks.node_security_group_id
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group (attached to node ENIs)"
  value       = module.eks.cluster_security_group_id
}

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = module.eks.configure_kubectl
}

output "amp_workspace_id" {
  description = "ID of the AWS Managed Prometheus (AMP) workspace for metrics"
  value       = module.eks.amp_workspace_id
}

output "amp_workspace_endpoint" {
  description = "HTTP (query) endpoint of the AMP workspace"
  value       = module.eks.amp_workspace_endpoint
}

output "amp_remote_write_url" {
  description = "Remote-write URL used by the ADOT collector's prometheusremotewrite exporter"
  value       = module.eks.amp_remote_write_url
}
