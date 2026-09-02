variable "vpc_id" {
  type        = string
  description = "ID of the VPC where the RDS instance will be created"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs of the private subnets for the DB subnet group"
}

variable "eks_node_security_group_id" {
  type        = string
  description = "Security group ID of the EKS node security group (allowed to connect to RDS on port 3306)"
}

variable "eks_cluster_security_group_id" {
  type        = string
  description = "Security group ID of the EKS-managed cluster security group (allowed to connect to RDS on port 3306)"
}

variable "secret_id" {
  type        = string
  default     = "retail-store/catalog/db2"
  description = "Name of the Secrets Manager secret containing DB credentials (RETAIL_CATALOG_PERSISTENCE_USER and RETAIL_CATALOG_PERSISTENCE_PASSWORD)"
}

variable "db_name" {
  type        = string
  default     = "catalogdb"
  description = "Name of the database to create"
}

variable "instance_class" {
  type        = string
  default     = "db.t3.micro"
  description = "RDS instance class"
}

variable "allocated_storage" {
  type        = number
  default     = 20
  description = "Allocated storage in GB"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
