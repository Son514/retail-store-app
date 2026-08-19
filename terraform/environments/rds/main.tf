# ------------------------------------------------------------------
# Remote state
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

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket       = "retail-store-dev-terraform-state"
    key          = "eks/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
  }
}

# ------------------------------------------------------------------
# RDS module
# ------------------------------------------------------------------

module "rds" {
  source = "../../modules/rds"

  vpc_id                     = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids         = data.terraform_remote_state.network.outputs.private_subnet_ids
  eks_node_security_group_id = data.terraform_remote_state.eks.outputs.cluster_security_group_id

  db_name = var.db_name

  tags = merge({
    "created-by" = "retail-store-app"
  }, var.tags)
}

# ------------------------------------------------------------------
# Catalog ConfigMap (updated with RDS endpoint)
# ------------------------------------------------------------------

resource "kubernetes_config_map" "catalog" {
  metadata {
    name      = "catalog-config"
    namespace = "development"

    labels = {
      "app.kubernetes.io/name"  = "catalog"
      "app.kubernetes.io/owner" = "retail-store-sample"
    }
  }

  data = {
    RETAIL_CATALOG_PERSISTENCE_PROVIDER = "mysql"
    RETAIL_CATALOG_PERSISTENCE_ENDPOINT = "${module.rds.address}:3306"
    RETAIL_CATALOG_PERSISTENCE_DB_NAME  = module.rds.db_name
    RETAIL_CATALOG_SEARCH_ENABLED       = "false"
  }
}
