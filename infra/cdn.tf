# Phase 7 -- Hosting layer: CDN fronting the Storage static website.
#
# Azure Front Door (Standard/Premium) is used here rather than "classic" Azure CDN
# (azurerm_cdn_profile/azurerm_cdn_endpoint) -- classic CDN profile/endpoint creation was
# deprecated by Microsoft on 2025-10-01 and the azurerm provider now rejects creating new
# ones (existing classic resources still work until the 2027-09-30 retirement, but this is
# a new resource, so classic isn't an option). Front Door Standard replaces it as Azure's
# current CDN offering.
#
# Standard_AzureFrontDoor (not Premium_AzureFrontDoor) is chosen -- this is a low-traffic
# hobby project (SPEC.md: cost matters), and Standard is the cheaper of the two tiers;
# Premium only adds WAF managed rules / private link support this project doesn't need.
#
# COST CAVEAT -- unlike the rest of this stack, Front Door Standard/Premium is NOT
# scale-to-zero: Microsoft bills a flat recurring monthly base fee per profile (on top of
# metered bandwidth/requests) regardless of traffic, a real departure from "classic" Azure
# CDN's pure pay-as-you-go model (which had no base fee). This is an accepted tradeoff, not
# an oversight -- classic CDN profile/endpoint creation is no longer available (deprecated
# 2025-10-01, see above), so Front Door is the only CDN option left for new resources, and
# SPEC.md calls for a CDN fronting the static site. This is the one piece of the
# infrastructure with non-zero idle cost; see PLAN.md's Phase 7 section for the same note.
#
# The origin must be the storage account's *static website* host
# (primary_web_host, e.g. <name>.z<n>.web.core.windows.net), not its blob endpoint
# (<name>.blob.core.windows.net) -- the blob endpoint doesn't understand static-website
# routing (index/error documents), so content fronted through it wouldn't resolve the way
# the static website does.

resource "azurerm_cdn_frontdoor_profile" "web" {
  name                = local.cdn_profile_name
  resource_group_name = data.azurerm_resource_group.main.name
  sku_name            = "Standard_AzureFrontDoor"

  tags = local.common_tags
}

resource "azurerm_cdn_frontdoor_endpoint" "web" {
  name                     = local.cdn_endpoint_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.web.id

  tags = local.common_tags
}

resource "azurerm_cdn_frontdoor_origin_group" "web" {
  name                     = "${local.cdn_endpoint_name}-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.web.id

  health_probe {
    protocol            = "Https"
    path                = "/"
    request_type        = "GET"
    interval_in_seconds = 100
  }

  load_balancing {}
}

resource "azurerm_cdn_frontdoor_origin" "web" {
  name                          = "${local.cdn_endpoint_name}-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.web.id

  # Origin against the storage static-website host, not the blob host -- see header comment.
  host_name          = azurerm_storage_account.web.primary_web_host
  origin_host_header = azurerm_storage_account.web.primary_web_host

  certificate_name_check_enabled = true
  http_port                      = 80
  https_port                     = 443
}

resource "azurerm_cdn_frontdoor_route" "web" {
  name                          = "${local.cdn_endpoint_name}-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.web.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.web.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.web.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
}
