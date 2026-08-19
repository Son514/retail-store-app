output "endpoint" {
  value       = aws_db_instance.rds.endpoint
  description = "RDS instance endpoint (host:port)"
}

output "address" {
  value       = aws_db_instance.rds.address
  description = "RDS instance hostname"
}

output "port" {
  value       = aws_db_instance.rds.port
  description = "RDS instance port"
}

output "db_name" {
  value       = aws_db_instance.rds.db_name
  description = "Name of the database"
}

output "security_group_id" {
  value       = aws_security_group.rds.id
  description = "Security group ID attached to the RDS instance"
}
