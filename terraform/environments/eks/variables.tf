variable "region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region (Singapore)"
}

variable "cluster_name" {
  type        = string
  default     = "retail-store"
  description = "Name of the EKS cluster (must match the kubernetes.io/cluster subnet tags in the network environment)"
}

variable "cluster_version" {
  type        = string
  default     = "1.35"
  description = "Kubernetes version for the EKS cluster"
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  default     = ["180.191.186.138/32"]
  description = "CIDRs allowed to reach the public EKS API endpoint"
}

variable "cluster_endpoint_private_access" {
  type        = bool
  default     = true
  description = "Whether the EKS cluster API endpoint is reachable from within the VPC"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
