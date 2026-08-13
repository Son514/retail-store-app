variable "region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region (Singapore)"
}

variable "bucket_name" {
  type        = string
  default     = "retail-store-dev-terraform-state"
  description = "Globally unique S3 bucket name that stores Terraform remote state"
}
