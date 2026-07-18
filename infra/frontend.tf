# Phase 8 -- Frontend application layer: upload the built static site into the Phase 7
# storage account's `$web` container.
#
# Consistent with the established pattern in functions.tf (zip_deploy_file): Terraform owns the
# deployed artifact directly, rather than a separate CI step (e.g. `az storage blob upload`).
# That keeps a single apply as the source of truth for what's live, with no out-of-band upload
# that a later `terraform apply` could silently fight or leave stale.
#
# content_md5 format: azurerm_storage_blob's `content_md5` is passed straight through to the
# blob's Content-MD5 property/header -- it is not independently validated by the Azure Storage
# service against the uploaded bytes, so its *encoding* doesn't affect whether the PUT succeeds.
# What matters for this repo's purposes is change detection: Terraform must see a different
# content_md5 value whenever the underlying file content changes, so it recomputes the diff and
# re-uploads instead of trusting a stale artifact (the same "path-string vs content-hash" lesson
# already learned from zip_deploy_file in functions.tf, applied here at the single-file level).
# `filemd5()` (hex-encoded MD5 digest) is what Terraform provides built-in for file-based content
# hashing -- there is no built-in "base64-encoded file MD5" function, so index.html/styles.css
# below use `filemd5()` directly. app.js isn't sourced from a file directly (see below), so its
# hash is computed with the built-in `md5()` function against the rendered string -- the direct
# analog of `filemd5()` for in-memory content, and the same hex-string format, so both blob types
# hash consistently. Live behavior (does an actual content change trigger a real re-upload) is
# confirmed per PLAN.md's Phase 8 verify step, same as every other layer in this repo.

locals {
  # app.js ships a placeholder (`__API_BASE_URL__`) instead of a hardcoded API origin, so it
  # can't drift from the actual deployed Function App. Plain string substitution, not
  # templatefile() -- templatefile() interprets `${...}` interpolation syntax, which would
  # collide with app.js's own JS template-literal syntax (e.g. `${API_BASE_URL}/api/todos`).
  app_js_content = replace(
    file("${path.module}/../web/app.js"),
    "__API_BASE_URL__",
    "https://${azurerm_linux_function_app.main.default_hostname}"
  )
}

resource "azurerm_storage_blob" "index_html" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/html"

  source      = "${path.module}/../web/index.html"
  content_md5 = filemd5("${path.module}/../web/index.html")
}

resource "azurerm_storage_blob" "styles_css" {
  name                   = "styles.css"
  storage_account_name   = azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/css"

  source      = "${path.module}/../web/styles.css"
  content_md5 = filemd5("${path.module}/../web/styles.css")
}

resource "azurerm_storage_blob" "app_js" {
  name                   = "app.js"
  storage_account_name   = azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "application/javascript"

  # Not a direct file source -- see the locals block above: app.js's __API_BASE_URL__
  # placeholder must be substituted with the live Function App hostname before upload.
  source_content = local.app_js_content
  content_md5    = md5(local.app_js_content)
}
