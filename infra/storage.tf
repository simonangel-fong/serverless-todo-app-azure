# Phase 7 -- Hosting layer: Storage static website.
#
# Deployed in `local.location` (the RG's own region), not `local.function_location`
# (Central US, picked only to dodge the Free Trial's 0-quota Microsoft.Web "Total VMs"
# restriction on Linux Consumption Function Apps -- see functions.tf/locals.tf). Storage
# accounts aren't gated by that VM quota, so there's no reason to move this off the RG's
# region.
#
# Enabling the static website (via the separate azurerm_storage_account_static_website
# resource below -- the inline `static_website` block on azurerm_storage_account is
# deprecated in provider v4 and slated for removal in v5) auto-creates the special `$web`
# container Phase 8 uploads the built frontend into, and turns on primary_web_endpoint --
# consumed directly as the frontend URL (outputs.tf's frontend_url) and as the CORS
# allow-list entry in functions.tf. There is no CDN in front of this endpoint: Azure Front
# Door is forbidden on this Free Trial/Student subscription, and classic Azure CDN can no
# longer be created for new resources as of 2025-10-01 (see SPEC.md/PLAN.md Phase 7).
#
# error_404_document is set to "index.html" rather than a dedicated 404 page: this is a
# single-page app with client-side routing (Phase 8), so unknown paths should still load
# the app shell rather than a bare storage error. Revisit if a distinct 404.html is ever
# added.

resource "azurerm_storage_account" "web" {
  name                = local.web_storage_account_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = local.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version = "TLS1_2"

  # Static website content in `$web` must be publicly readable over HTTPS for browsers to
  # fetch it directly (no CDN in front -- see header comment) -- unlike functions.tf's
  # runtime storage account, this one is meant to serve public content.
  allow_nested_items_to_be_public = true

  tags = local.common_tags
}

resource "azurerm_storage_account_static_website" "web" {
  storage_account_id = azurerm_storage_account.web.id

  index_document     = "index.html"
  error_404_document = "index.html"
}
