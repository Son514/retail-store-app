variable "region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region (Singapore)"
}

variable "environment_name" {
  type        = string
  default     = "dev"
  description = "Name of the environment, used in resource names and tags"
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
