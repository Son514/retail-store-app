# ------------------------------------------------------------------
# ECR module
# ------------------------------------------------------------------

module "ecr" {
  source = "../../modules/ecr"

  repository_names = concat(var.config.repositories, var.config.chart_repositories)

  tags = merge({
    "created-by" = "retail-store-app"
  }, var.config.tags)
}
