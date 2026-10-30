# Values Terraform prints after apply (and with `terraform output`).

# Full names of all lakehouse schemas, e.g. "workspace.bronze"
output "schemas" {
  value = {
    bronze     = databricks_schema.bronze.id
    silver     = databricks_schema.silver.id
    gold       = databricks_schema.gold.id
    staging    = databricks_schema.staging.id
    audit      = databricks_schema.audit.id
    restricted = databricks_schema.restricted.id
  }
}

# Path the notebooks use to read the raw files, e.g. /Volumes/workspace/bronze/landing
output "landing_volume_path" {
  value = databricks_volume.landing.volume_path
}
