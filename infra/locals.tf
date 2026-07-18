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

  # Cosmos account deployed in a different region than the RG's `location` (East US) --
  # a resource's region doesn't have to match its resource group's, which is just a
  # management container. East US was repeatedly out of capacity for new serverless
  # Cosmos accounts (ServiceUnavailable on create); East US 2 is its standard paired
  # region and commonly has separate capacity.
  cosmos_location = "eastus2"

  # Function App resources deployed in Central US rather than the RG's `location` (East US) or
  # East US 2 -- this subscription is a Free Trial, whose Microsoft.Web "Total Regional VMs"
  # quota (backing Linux Consumption/Y1 plans) is 0 in both East US and East US 2, confirmed via
  # `az functionapp create --consumption-plan-location` test creates: East US/East US 2 both
  # fail with a 401 quota error, while Central US, West US 2, and North Europe all succeed. Free
  # Trial subscriptions aren't eligible for quota increases (Microsoft's own guidance), so the
  # working region is picked directly rather than requesting more quota.
  function_location = "centralus"

  # Phase 5 — compute (Function App). Hyphens are fine in these names (Function App /
  # Service Plan naming rules allow them), so they follow the same "<project>-<env>-<suffix>"
  # convention as Cosmos above.
  function_app_name  = "${local.project}-${local.environment}-func"
  function_plan_name = "${local.project}-${local.environment}-func-plan"

  # Functions requires its own Storage Account (queues/blobs for the runtime, host key
  # storage, deployment package). Storage account names must be globally unique, 3-24
  # chars, lowercase alphanumeric only (no hyphens) -- derived from project/environment
  # rather than hardcoded, same rationale as cosmos_account_name above. Named distinctly
  # ("...func") so it can never collide with the Phase 7 static-website storage account.
  function_storage_account_name = substr(
    lower(replace("${local.project}${local.environment}func", "-", "")),
    0, 24
  )
}
