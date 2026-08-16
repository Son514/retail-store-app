# ------------------------------------------------------------------
# Remote state (VPC outputs from the network environment)
# ------------------------------------------------------------------

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket       = "retail-store-dev-terraform-state"
    key          = "network/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
  }
}

# ------------------------------------------------------------------
# EKS module
# ------------------------------------------------------------------

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr           = data.terraform_remote_state.network.outputs.vpc_cidr
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  cluster_version    = var.cluster_version

  node_group_instance_types = ["t3.small"]

  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_endpoint_private_access      = var.cluster_endpoint_private_access

  tags = merge({
    "created-by" = "retail-store-app"
  }, var.tags)
}
