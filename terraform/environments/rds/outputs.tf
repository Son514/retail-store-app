output "rds_endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = module.rds.endpoint
}

output "rds_address" {
  description = "RDS instance hostname"
  value       = module.rds.address
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.rds.port
}

output "rds_db_name" {
  description = "Name of the database"
  value       = module.rds.db_name
}
