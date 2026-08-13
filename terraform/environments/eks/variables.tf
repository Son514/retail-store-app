variable "region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region (Singapore)"
}

variable "environment_name" {
  type        = string
  default     = "dev"
  description = "Name of the environment; must match the kubernetes.io/cluster subnet tags"
}

variable "cluster_version" {
  type        = string
  default     = "1.33"
  description = "Kubernetes version for the EKS cluster"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
