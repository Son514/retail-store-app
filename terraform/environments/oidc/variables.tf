variable "config" {
  description = "Deployment configuration shared across all environments; set in ../shared.tfvars (see shared.tfvars.example). Keys unused by this environment are ignored."
  type = object({
    region                               = optional(string, "ap-southeast-1")
    tags                                 = optional(map(string), {})
    cluster_name                         = optional(string, "retail-store")
    vpc_cidr                             = optional(string, "10.0.0.0/16")
    state_bucket                         = optional(string, "retail-store-dev-terraform-state")
    cluster_version                      = optional(string, "1.35")
    cluster_endpoint_public_access_cidrs = optional(list(string))
    cluster_endpoint_private_access      = optional(bool, true)
    node_group_instance_types            = optional(list(string), ["t3.small"])
    node_group_desired_size              = optional(number, 2)
    repositories                         = optional(list(string), ["ui", "catalog", "cart", "checkout", "orders", "test-tools"])
    chart_repositories                   = optional(list(string), ["charts/catalog", "charts/ui"])
    db_name                              = optional(string, "catalogdb")
    namespaces                           = optional(list(string), ["development", "production"])
    secret_id                            = optional(string, "retail-store/catalog/db2")
  })
}
