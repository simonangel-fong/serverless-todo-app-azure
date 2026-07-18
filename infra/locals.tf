locals {
  project     = var.project_name
  environment = var.environment

  # Well-known resource group name — must match the literal name created and owned by
  # the canonical identity repo (serverless-todo-app-azure.tf). This repo does not create
  # the RG; it only references it (see rg.tf's data source). Keep this string in sync with
  # that repo's `local.serverless_todoapp_name` if it ever changes there.
  resource_group_name = "serverless-todoapp-dev"

  # Derived from the existing RG rather than a separate variable, so later layers
  # (Cosmos, Storage/CDN, Functions) can't drift from where the RG actually lives.
  location = data.azurerm_resource_group.main.location

  common_tags = merge(var.tags, {
    project     = local.project
    environment = local.environment
    managed_by  = "terraform"
  })
}
