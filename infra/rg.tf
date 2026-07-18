# The foundation resource group every later layer (Cosmos, Storage/CDN, Functions) deploys
# into. It is created and owned by the canonical identity repo
# (serverless-todo-app-azure.tf) — this repo only references it. The Contributor grant
# used by CI is subscription-scoped (see docs/rbac.md), so there is no create-before-grant
# ordering dependency between the two repos.

data "azurerm_resource_group" "main" {
  name = local.resource_group_name
}