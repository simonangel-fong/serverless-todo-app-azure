terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # State lives in an existing S3 bucket (AWS), managed outside this repo.
  # Concrete bucket/key/region come from -backend-config=backend.hcl at init time
  # (see backend.hcl.example) — never committed here.
  backend "s3" {}
}

provider "azurerm" {
  features {}
}
