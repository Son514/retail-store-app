output "cluster_id" {
  description = "ID of the EKS cluster"
  value       = aws_eks_cluster.this.id
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster API server"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Certificate authority data of the EKS cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_security_group_id" {
  description = "ID of the node security group"
  value       = aws_security_group.node.id
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role used by the managed node group"
  value       = aws_iam_role.node.arn
}

output "aws_lb_controller_release" {
  description = "Helm release ID of the AWS Load Balancer Controller (installed and ready)"
  value       = helm_release.aws_lb_controller.id
}

output "node_group_id" {
  description = "ID of the managed node group"
  value       = aws_eks_node_group.this.id
}

output "node_group_arn" {
  description = "ARN of the managed node group"
  value       = aws_eks_node_group.this.arn
}

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks --region ${data.aws_region.current.region} update-kubeconfig --name ${aws_eks_cluster.this.name}"
}
