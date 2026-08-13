module "vpc" {
  source = "../../modules/vpc"

  environment_name = var.environment_name
  vpc_cidr         = var.vpc_cidr
  tags = merge({
    "environment-name" = var.environment_name
    "created-by"       = "retail-store-app"
  }, var.tags)
}
