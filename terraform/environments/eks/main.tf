# ------------------------------------------------------------------
# Remote state (VPC outputs from the network environment)
# ------------------------------------------------------------------

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket       = var.config.state_bucket
    key          = "network/terraform.tfstate"
    region       = var.config.region
    use_lockfile = true
  }
}

# ------------------------------------------------------------------
# EKS module
# ------------------------------------------------------------------

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.config.cluster_name
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr           = data.terraform_remote_state.network.outputs.vpc_cidr
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  cluster_version    = var.config.cluster_version
  secret_id          = var.config.secret_id

  node_group_instance_types = var.config.node_group_instance_types
  node_group_desired_size   = var.config.node_group_desired_size

  cluster_endpoint_public_access_cidrs = var.config.cluster_endpoint_public_access_cidrs
  cluster_endpoint_private_access      = var.config.cluster_endpoint_private_access
  adot_addon_version                   = var.config.adot_addon_version

  tags = merge({
    "created-by" = "retail-store-app"
  }, var.config.tags)
}

# ------------------------------------------------------------------
# Karpenter — spot instance node pool
# ------------------------------------------------------------------

module "karpenter" {
  source = "../../modules/karpenter"

  cluster_name                       = module.eks.cluster_name
  cluster_endpoint                   = module.eks.cluster_endpoint
  cluster_version                    = var.config.cluster_version
  cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
  vpc_id                             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids                 = data.terraform_remote_state.network.outputs.private_subnet_ids
  node_security_group_id             = module.eks.node_security_group_id
  node_iam_role_arn                  = module.eks.node_iam_role_arn
  aws_lb_controller_release          = module.eks.aws_lb_controller_release

  tags = merge({
    "created-by" = "retail-store-app"
  }, var.config.tags)
}
