# Stub for now — later phases add their own outputs as real resources land:
#   Phase 4 (cosmos.tf)    -> cosmos account endpoint
#   Phase 5 (storage/cdn)  -> CDN endpoint hostname (frontend origin)
#   Phase 6 (functions.tf) -> Function App default hostname (api url)

output "resource_group_name" {
  description = "Well-known resource group name, created and owned by the canonical identity repo; referenced here via data source."
  value       = data.azurerm_resource_group.main.name
}

output "location" {
  description = "Azure region resources are deployed into (derived from the existing resource group)."
  value       = data.azurerm_resource_group.main.location
}
