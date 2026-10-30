# Which Terraform and which provider versions this folder works with.
terraform {
  # 1.5 or newer is needed for the import blocks in main.tf
  required_version = ">= 1.5"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.50" # any 1.x from 1.50 up, never 2.0 (which could have breaking changes)
    }
  }
}

# Empty on purpose: the provider reads DATABRICKS_HOST and DATABRICKS_TOKEN from environment
# variables set in my own terminal, so no workspace URL or token is ever written in this repo.
provider "databricks" {}
