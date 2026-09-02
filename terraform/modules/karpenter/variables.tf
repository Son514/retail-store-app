variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "cluster_endpoint" {
  type        = string
  description = "Endpoint of the EKS cluster API server"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
}

variable "cluster_certificate_authority_data" {
  type        = string
  description = "Base64-encoded certificate authority data for the EKS cluster"
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC where the EKS cluster resides"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs of the private subnets for Karpenter-managed nodes"
}

variable "node_security_group_id" {
  type        = string
  description = "Security group ID to attach to Karpenter-managed nodes"
}

variable "node_iam_role_arn" {
  type        = string
  description = "ARN of the IAM role for Karpenter-managed nodes (must have AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}

variable "aws_lb_controller_release" {
  type        = string
  description = "Helm release ID of the AWS Load Balancer Controller (ensures its webhook is ready before Karpenter resources are created)"
}
