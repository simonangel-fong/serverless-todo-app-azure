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

  # Cosmos DB account names must be globally unique across Azure (lowercase alphanumeric
  # + hyphens, 3-44 chars). Derived from project/environment rather than hardcoded so it
  # can't drift from the naming convention used elsewhere in this repo.
  cosmos_account_name  = "${local.project}-${local.environment}-cosmos"
  cosmos_database_name = "${local.project}-${local.environment}-db"
}
