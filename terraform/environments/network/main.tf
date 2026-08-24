# ------------------------------------------------------------------
# VPC module
# ------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr = var.config.vpc_cidr
  tags = merge({
    "created-by" = "retail-store-app"
  }, var.config.tags)

  # EKS subnet tags (public): required by the LoadBalancer service type.
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.config.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                           = "1"
  }

  # EKS subnet tags (private): required for internal load balancers.
  private_subnet_tags = {
    "kubernetes.io/cluster/${var.config.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"                  = "1"
  }
}
