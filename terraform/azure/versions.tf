# Which Terraform and which provider versions this folder works with.
# VALIDATE-ONLY: checked in CI, never deployed (no Azure subscription yet). See README.md.
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" # any 4.x, never 5.0
    }
  }
}

# Azure login would come from environment variables or `az login` (nothing is stored here).
# features {} is required by the azurerm provider, even when empty.
provider "azurerm" {
  features {}
}
