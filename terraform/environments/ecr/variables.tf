variable "region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region (Singapore)"
}

variable "repositories" {
  type        = list(string)
  default     = ["ui", "catalog", "cart", "checkout", "orders"]
  description = "Microservice repositories to create in ECR"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
