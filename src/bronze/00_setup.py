# Databricks notebook source
# MAGIC %md
# MAGIC # 00_setup - Day 5: create the lakehouse structure
# MAGIC Creates the three medallion schemas and the landing volume for raw files.
# MAGIC Safe to rerun: `IF NOT EXISTS` skips anything that already exists (idempotent).
# MAGIC
# MAGIC ```
# MAGIC workspace (catalog)
# MAGIC   bronze  -> raw tables + landing volume for CSV files
# MAGIC   silver  -> clean, typed tables
# MAGIC   gold    -> business-ready star schema
# MAGIC ```

# COMMAND ----------

# MAGIC %sql
# MAGIC -- CELL 1 - Create the schemas and the landing volume
# MAGIC -- %sql at the top switches this cell from Python to SQL.
# MAGIC
# MAGIC -- A schema is a folder for tables inside the "workspace" catalog.
# MAGIC CREATE SCHEMA IF NOT EXISTS workspace.bronze;   -- raw data, exactly as received
# MAGIC CREATE SCHEMA IF NOT EXISTS workspace.silver;   -- cleaned, typed, deduplicated data
# MAGIC CREATE SCHEMA IF NOT EXISTS workspace.gold;     -- business-ready tables for reporting
# MAGIC
# MAGIC -- A volume stores FILES (like CSVs) inside a schema. "landing" is where raw files first arrive.
# MAGIC CREATE VOLUME IF NOT EXISTS workspace.bronze.landing;

# COMMAND ----------

# CELL 2 - Check that all 9 CSVs are in the landing folder
# After uploading the files (Catalog > workspace > bronze > Volumes > landing > olist > Upload),
# this lists them. dbutils.fs.ls = "list files", like dir on Windows.
display(dbutils.fs.ls("/Volumes/workspace/bronze/landing/olist/"))

# Expect: 9 rows, one per CSV. geolocation is the largest (about 60 MB).
