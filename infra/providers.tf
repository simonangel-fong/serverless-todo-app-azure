terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # State lives in an Azure Storage account + blob container, created and owned by the
  # canonical identity repo (see docs/rbac.md). Same OIDC principal used by the azurerm
  # provider below also authenticates the backend (its Contributor grant includes
  # listKeys on the storage account) — no separate credentials needed.
  # Concrete resource_group_name/storage_account_name/container_name/key come from
  # -backend-config=backend.hcl at init time (see backend.hcl.example) — never committed here.
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}
