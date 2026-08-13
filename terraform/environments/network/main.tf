# ------------------------------------------------------------------
# VPC module
# ------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  environment_name = var.environment_name
  vpc_cidr         = var.vpc_cidr
  tags = merge({
    "environment-name" = var.environment_name
    "created-by"       = "retail-store-app"
  }, var.tags)

  # EKS subnet tags (public): required by the LoadBalancer service type.
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.environment_name}" = "shared"
    "kubernetes.io/role/elb"                        = "1"
  }

  # EKS subnet tags (private): required for internal load balancers.
  private_subnet_tags = {
    "kubernetes.io/cluster/${var.environment_name}" = "shared"
    "kubernetes.io/role/internal-elb"               = "1"
  }
}
