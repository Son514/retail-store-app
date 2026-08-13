data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket       = "retail-store-dev-terraform-state"
    key          = "network/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
  }
}

module "eks" {
  source = "../../modules/eks"

  environment_name   = var.environment_name
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr           = data.terraform_remote_state.network.outputs.vpc_cidr
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  cluster_version    = var.cluster_version

  tags = merge({
    "environment-name" = var.environment_name
    "created-by"       = "retail-store-app"
  }, var.tags)
}
