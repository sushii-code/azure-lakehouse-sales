# Unity Catalog objects of the lakehouse, managed as code.
#
# All of them already exist (created by the notebooks and dbt), so each one has an import
# block: on the first `terraform apply`, Terraform adopts the existing object into its state
# instead of trying to create it again. After that, `terraform plan` should show no changes.
#
# The settings are kept minimal (name and catalog only) so they match what already exists.
# prevent_destroy stops Terraform from ever deleting a schema (and every table in it) by mistake.
#
# Not managed here yet: the Databricks job. It is documented in jobs/olist_lakehouse_pipeline.yml.

locals {
  catalog = "workspace" # the Unity Catalog catalog of Databricks Free Edition
}

# ---------- Schemas (one per lakehouse layer) ----------

# Raw data exactly as received, plus the landing volume
resource "databricks_schema" "bronze" {
  catalog_name = local.catalog
  name         = "bronze"

  lifecycle {
    prevent_destroy = true
  }
}

# Cleaned, typed tables and their quarantine tables
resource "databricks_schema" "silver" {
  catalog_name = local.catalog
  name         = "silver"

  lifecycle {
    prevent_destroy = true
  }
}

# dbt star schema (facts and dimensions)
resource "databricks_schema" "gold" {
  catalog_name = local.catalog
  name         = "gold"

  lifecycle {
    prevent_destroy = true
  }
}

# dbt staging views
resource "databricks_schema" "staging" {
  catalog_name = local.catalog
  name         = "staging"

  lifecycle {
    prevent_destroy = true
  }
}

# dbt reconciliation report
resource "databricks_schema" "audit" {
  catalog_name = local.catalog
  name         = "audit"

  lifecycle {
    prevent_destroy = true
  }
}

# Simulated personal data and the token vault
resource "databricks_schema" "restricted" {
  catalog_name = local.catalog
  name         = "restricted"

  lifecycle {
    prevent_destroy = true
  }
}

# ---------- Volume ----------

# Folder-like storage where the raw Olist CSVs are uploaded before bronze ingestion
resource "databricks_volume" "landing" {
  catalog_name = local.catalog
  schema_name  = databricks_schema.bronze.name
  name         = "landing"
  volume_type  = "MANAGED" # Databricks manages the storage location

  lifecycle {
    prevent_destroy = true
  }
}

# ---------- Import blocks (adopt the objects that already exist) ----------
# id format: "<catalog>.<schema>" for a schema, "<catalog>.<schema>.<volume>" for a volume

import {
  to = databricks_schema.bronze
  id = "workspace.bronze"
}

import {
  to = databricks_schema.silver
  id = "workspace.silver"
}

import {
  to = databricks_schema.gold
  id = "workspace.gold"
}

import {
  to = databricks_schema.staging
  id = "workspace.staging"
}

import {
  to = databricks_schema.audit
  id = "workspace.audit"
}

import {
  to = databricks_schema.restricted
  id = "workspace.restricted"
}

import {
  to = databricks_volume.landing
  id = "workspace.bronze.landing"
}
