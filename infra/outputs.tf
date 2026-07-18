# Stub for now — later phases add their own outputs as real resources land:
#   Phase 5 (storage/cdn)  -> CDN endpoint hostname (frontend origin)
#   Phase 6 (functions.tf) -> Function App default hostname (api url)

output "cosmos_account_endpoint" {
  description = "Cosmos DB account document endpoint, consumed by the Phase 6 Function App app settings."
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "resource_group_name" {
  description = "Well-known resource group name, created and owned by the canonical identity repo; referenced here via data source."
  value       = data.azurerm_resource_group.main.name
}

output "location" {
  description = "Azure region resources are deployed into (derived from the existing resource group)."
  value       = data.azurerm_resource_group.main.location
}
