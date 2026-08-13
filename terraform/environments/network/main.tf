module "vpc" {
  source = "../../modules/vpc"

  environment_name = var.environment_name
  vpc_cidr         = var.vpc_cidr
  tags = merge({
    "environment-name" = var.environment_name
    "created-by"       = "retail-store-app"
  }, var.tags)

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.environment_name}" = "shared"
    "kubernetes.io/role/elb"                        = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.environment_name}" = "shared"
    "kubernetes.io/role/internal-elb"               = "1"
  }
}
