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

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
