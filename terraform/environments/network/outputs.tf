output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr
}

output "availability_zones" {
  description = "Availability zones used for the subnets"
  value       = module.vpc.azs
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = module.vpc.public_route_table_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = module.vpc.private_route_table_id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway"
  value       = module.vpc.nat_gateway_id
}

output "nat_eip" {
  description = "Elastic IP address attached to the NAT gateway"
  value       = module.vpc.nat_eip
}
