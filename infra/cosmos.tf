# Phase 4 — Data layer: Cosmos DB (serverless, NoSQL/Core API).
#
# Serverless capacity mode is a hard project constraint (SPEC.md: scale-to-zero) — no
# provisioned/autoscale throughput is set anywhere in this file. Setting `throughput` or
# `autoscale_settings` on the database/container of a serverless account fails apply, so
# neither is configured here on purpose.

resource "azurerm_cosmosdb_account" "main" {
  name                = local.cosmos_account_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = local.cosmos_location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB" # Core (SQL/NoSQL) API

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = local.cosmos_location
    failover_priority = 0
    zone_redundant    = false # avoid AZ-redundant capacity/cost; not needed for a single dev environment
  }

  tags = local.common_tags
}

resource "azurerm_cosmosdb_sql_database" "main" {
  name                = local.cosmos_database_name
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

resource "azurerm_cosmosdb_sql_container" "todos" {
  name                = "todos"
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_paths = ["/id"]
}
