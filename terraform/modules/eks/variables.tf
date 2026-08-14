variable "environment_name" {
  type        = string
  description = "Name of the environment, used for the cluster name and tags (must match the kubernetes.io/cluster subnet tags)"
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC where the EKS cluster will be created"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block of the VPC, used for node security group DNS rules"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs of the private subnets used by the cluster control plane and nodes"
}

variable "cluster_version" {
  type        = string
  default     = "1.35"
  description = "Kubernetes version for the EKS cluster"
}

variable "cluster_endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS cluster API endpoint is reachable from the public internet"
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API endpoint"
}

variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.micro"]
  description = "Instance types for the managed node group (account is free-tier restricted, so non-free-tier types like m5.large fail to launch)"
}

variable "node_group_desired_size" {
  type        = number
  default     = 1
  description = "Desired number of nodes in the managed node group"
}

variable "node_group_min_size" {
  type        = number
  default     = 1
  description = "Minimum number of nodes in the managed node group"
}

variable "node_group_max_size" {
  type        = number
  default     = 3
  description = "Maximum number of nodes in the managed node group"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
