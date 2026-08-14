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

variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to the public subnets"
}

variable "private_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to the private subnets"
}
