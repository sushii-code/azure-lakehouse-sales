# terraform/azure (validate-only)

This folder describes the Azure storage the lakehouse would use in production:

- a resource group (`<prefix>-rg`, region `uksouth` by default)
- an ADLS Gen2 storage account (`<prefix>lake`) with hierarchical namespace on, TLS 1.2 minimum, HTTPS only and public blob access disabled
- three private containers: `bronze`, `silver`, `gold`

## Why it is not deployed

I do not have an Azure subscription yet, so this code has never been applied. It is still checked on every push: the CI `terraform` job runs `terraform fmt -check`, `terraform init -backend=false` and `terraform validate`, which prove the code is well formatted and correct Terraform without logging in to Azure or creating anything.

The working version of the project runs on Databricks Free Edition, whose storage is managed by Databricks. The real, applied Terraform for that lives in [`../databricks`](../databricks).

## How it maps to the Databricks schemas

| Azure container | Databricks schema today | Holds |
| --- | --- | --- |
| `bronze` | `workspace.bronze` (+ volume `landing`) | Raw files and raw Delta tables |
| `silver` | `workspace.silver` | Cleaned, typed tables and quarantine tables |
| `gold` | `workspace.gold` | dbt star schema |

On Azure Databricks, each container would be registered in Unity Catalog as an external location (for example `abfss://bronze@<prefix>lake.dfs.core.windows.net/`) and used as the storage root of the matching schema. `staging`, `audit` and `restricted` would sit under the silver or gold storage, with `restricted` behind its own access controls.

## To deploy later

1. `az login` (or set the `ARM_*` environment variables); add `subscription_id` to the provider (required by azurerm 4.x for plan/apply).
2. Choose a globally unique `name_prefix`.
3. Add a remote backend (an Azure storage container for the Terraform state).
4. `terraform init`, `terraform plan`, review, then `terraform apply`.
