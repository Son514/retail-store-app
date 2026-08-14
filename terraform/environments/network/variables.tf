variable "region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region (Singapore)"
}

variable "cluster_name" {
  type        = string
  default     = "retail-store"
  description = "Name of the EKS cluster; used in the kubernetes.io/cluster subnet tags (must match the eks environment)"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
