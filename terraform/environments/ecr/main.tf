# ------------------------------------------------------------------
# ECR module
# ------------------------------------------------------------------

module "ecr" {
  source = "../../modules/ecr"

  repository_names = var.repositories

  tags = merge({
    "created-by" = "retail-store-app"
  }, var.tags)
}
