# ------------------------------------------------------------------
# Secrets Manager
# ------------------------------------------------------------------

data "aws_secretsmanager_secret_version" "catalog_db" {
  secret_id = var.secret_id
}

locals {
  db_credentials = jsondecode(data.aws_secretsmanager_secret_version.catalog_db.secret_string)
  db_username    = local.db_credentials["RETAIL_CATALOG_PERSISTENCE_USER"]
  db_password    = local.db_credentials["RETAIL_CATALOG_PERSISTENCE_PASSWORD"]
}

# ------------------------------------------------------------------
# Security group
# ------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "rds-catalog"
  description = "Security group for catalog RDS instance"
  vpc_id      = var.vpc_id

  tags = var.tags
}

resource "aws_security_group_rule" "rds_ingress" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = var.eks_node_security_group_id
  security_group_id        = aws_security_group.rds.id
}

resource "aws_security_group_rule" "rds_ingress_cluster" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = var.eks_cluster_security_group_id
  security_group_id        = aws_security_group.rds.id
}

resource "aws_security_group_rule" "rds_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
}

# ------------------------------------------------------------------
# DB subnet group
# ------------------------------------------------------------------

resource "aws_db_subnet_group" "rds" {
  name       = "catalog-rds"
  subnet_ids = var.private_subnet_ids

  tags = var.tags
}

# ------------------------------------------------------------------
# RDS instance
# ------------------------------------------------------------------

resource "aws_db_instance" "rds" {
  identifier = "catalog"

  engine         = "mysql"
  engine_version = "8.4"
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true
  db_name           = var.db_name
  username          = local.db_username
  password          = local.db_password
  port              = 3306

  multi_az                = false
  db_subnet_group_name    = aws_db_subnet_group.rds.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 0
  deletion_protection     = false

  tags = var.tags
}
