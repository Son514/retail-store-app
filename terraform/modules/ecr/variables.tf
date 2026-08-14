variable "repository_names" {
  type        = list(string)
  description = "Names of the ECR repositories to create"
}

variable "image_tag_mutability" {
  type        = string
  default     = "IMMUTABLE"
  description = "Tag mutability for the repositories (IMMUTABLE prevents overwriting a tag)"
}

variable "expire_untagged_days" {
  type        = number
  default     = 7
  description = "Number of days after which untagged images are expired"
}

variable "keep_tagged_images" {
  type        = number
  default     = 10
  description = "Number of tagged images to keep per repository"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
