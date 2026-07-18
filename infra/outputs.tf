output "cdn_endpoint_hostname" {
  description = "CDN endpoint hostname fronting the Phase 7 static website (frontend origin), consumed by Phase 8's deploy step and by Phase 5's Function App CORS allow-list."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.web.host_name}"
}

output "cosmos_account_endpoint" {
  description = "Cosmos DB account document endpoint, consumed by the Phase 5 Function App app settings."
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "function_app_default_hostname" {
  description = "Function App default hostname (api url), consumed by Phase 8's frontend as the API base URL."
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "resource_group_name" {
  description = "Well-known resource group name, created and owned by the canonical identity repo; referenced here via data source."
  value       = data.azurerm_resource_group.main.name
}

output "location" {
  description = "Azure region resources are deployed into (derived from the existing resource group)."
  value       = data.azurerm_resource_group.main.location
}
