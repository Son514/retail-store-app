# ------------------------------------------------------------------
# Remote state
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

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket       = var.config.state_bucket
    key          = "eks/terraform.tfstate"
    region       = var.config.region
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

  db_name   = var.config.db_name
  secret_id = var.config.secret_id

  tags = merge({
    "created-by" = "retail-store-app"
  }, var.config.tags)
}

# ------------------------------------------------------------------
# Namespaces
# ------------------------------------------------------------------

resource "kubernetes_namespace" "app" {
  for_each = toset(var.config.namespaces)

  metadata {
    name = each.value

    labels = {
      "app.kubernetes.io/owner" = "retail-store-app"
    }
  }
}

# ------------------------------------------------------------------
# Catalog ConfigMap (updated with RDS endpoint)
# ------------------------------------------------------------------

resource "kubernetes_config_map" "catalog" {
  for_each = toset(var.config.namespaces)

  metadata {
    name      = "catalog-config"
    namespace = each.value

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

  depends_on = [kubernetes_namespace.app]
}
