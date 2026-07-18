# Phase 5 — Compute layer: Function App (Python, Consumption plan).
#
# Consumption plan (SKU "Y1") is a hard project constraint (SPEC.md: scale-to-zero) — it bills
# per-execution and scales to zero instances when idle, unlike a Premium/Dedicated plan. No
# always-on setting is configured anywhere in this file on purpose.
#
# Cosmos connectivity: a key-based connection (endpoint + primary key, both flowing from
# infra/cosmos.tf resource attributes -- never hardcoded) is used instead of AAD/managed-identity
# auth. The CI principal only holds subscription-scoped Contributor, which explicitly excludes
# Microsoft.Authorization/roleAssignments/write (see docs/rbac.md) -- so an
# azurerm_role_assignment for the Function App's managed identity would fail to apply from this
# repo's pipeline. No infra/rbac.tf is added as a result; app settings carry the Cosmos
# credentials via resource attribute references, not literal secrets.
#
# CORS: the CDN endpoint origin (infra/cdn.tf, Phase 7) is added to site_config.cors below --
# landed as the deliberate follow-up cross-phase edit PLAN.md calls for once that origin
# exists. Previously left unset here pending Phase 7.
#
# Code deployment: this resource owns the deployed code artifact directly via zip_deploy_file
# (var.function_app_zip_path, supplied by CI on every apply). No separate CI action (e.g.
# Azure/functions-action) deploys app code or writes app_settings outside Terraform -- doing so
# previously left an out-of-band WEBSITE_RUN_FROM_PACKAGE setting on the live app that the next
# `terraform apply` would silently wipe, since app_settings here is authoritative. Terraform now
# owns app_settings and the code artifact together to eliminate that drift/wipe risk.
#
# WEBSITE_RUN_FROM_PACKAGE = "1" (in app_settings below) is a required companion to
# zip_deploy_file, not optional -- the azurerm provider's zip_deploy_file schema requires either
# this setting or SCM_DO_BUILD_DURING_DEPLOYMENT=true to be present. This project vendors Python
# deps into .python_packages/lib/site-packages before deploy (no remote/Oryx build), so
# WEBSITE_RUN_FROM_PACKAGE is the correct one; SCM_DO_BUILD_DURING_DEPLOYMENT would trigger an
# unwanted Oryx build against the zip contents.

resource "azurerm_storage_account" "functions" {
  name                = local.function_storage_account_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = local.function_location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = local.common_tags
}

resource "azurerm_service_plan" "functions" {
  name                = local.function_plan_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = local.function_location

  os_type  = "Linux" # Linux is required for the Python worker runtime
  sku_name = "Y1"    # Consumption plan -- pay-per-execution, scales to zero when idle

  tags = local.common_tags
}

resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = local.function_location

  service_plan_id            = azurerm_service_plan.functions.id
  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key

  https_only = true # reject plaintext HTTP on the API endpoint

  zip_deploy_file = var.function_app_zip_path

  site_config {
    application_stack {
      python_version = "3.11"
    }

    # Phase 7's CDN endpoint is the frontend's origin -- allowed here so browser fetches
    # from the hosted static site to this API succeed (see infra/cdn.tf).
    #
    # NOTE on convergence: allowed_origins is a `set(string)`, and this value is unknown
    # during the very first apply that creates infra/cdn.tf's endpoint alongside this
    # change (Terraform/terraform-plugin-sdk have a long-standing limitation where a
    # brand-new Set whose only elements are unknown-at-plan-time values can fail to show
    # as a pending diff -- see hashicorp/terraform-plugin-sdk#1210). If `terraform plan`
    # right after landing this shows no change to `cors` even though the CDN endpoint is
    # new, re-run `terraform plan`/apply once more: after the endpoint exists in state its
    # host_name is a known value, and the diff against the still-empty live `cors` will
    # then be detected normally. Confirm via `az functionapp cors show` per PLAN.md's
    # Phase 7 verify step.
    cors {
      allowed_origins = ["https://${azurerm_cdn_frontdoor_endpoint.web.host_name}"]
    }
  }

  app_settings = {
    # Phase 6's Python API code connects to Cosmos using these -- values are resource
    # attributes from infra/cosmos.tf, never literal/committed secrets.
    COSMOS_DB_ENDPOINT  = azurerm_cosmosdb_account.main.endpoint
    COSMOS_DB_KEY       = azurerm_cosmosdb_account.main.primary_key
    COSMOS_DB_DATABASE  = azurerm_cosmosdb_sql_database.main.name
    COSMOS_DB_CONTAINER = azurerm_cosmosdb_sql_container.todos.name

    # Required companion to zip_deploy_file above -- tells the platform to run directly from the
    # deployed package instead of expecting an Oryx build. See header comment for why this
    # setting (not SCM_DO_BUILD_DURING_DEPLOYMENT) is correct for this project.
    WEBSITE_RUN_FROM_PACKAGE = "1"
  }

  tags = local.common_tags
}
