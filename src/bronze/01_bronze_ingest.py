# Databricks notebook source
# MAGIC %md
# MAGIC # 01_bronze_ingest - Day 5: load the raw Olist files into bronze
# MAGIC Bronze keeps the data **exactly as received** (every column as text), plus two audit columns:
# MAGIC when each row was loaded and which file it came from.
# MAGIC
# MAGIC | Step | Does |
# MAGIC | --- | --- |
# MAGIC | 1 | Read one CSV and look at its structure |
# MAGIC | 2 | Peek at rows and count them |
# MAGIC | 3 | Load all 9 CSVs into bronze Delta tables |
# MAGIC | 4 | Reconcile: bronze row counts must match the source files |
# MAGIC
# MAGIC **Before running:** the 9 CSVs must be in the volume folder `/Volumes/workspace/bronze/landing/olist/`
# MAGIC (created by `00_setup`). Run each cell from top to bottom with **Shift + Enter**.

# COMMAND ----------

# CELL 1 - Read one CSV and see its columns

# The address of the orders file inside the Unity Catalog volume.
path = "/Volumes/workspace/bronze/landing/olist/olist_orders_dataset.csv"

# spark = the connection to the Spark engine that Databricks gives every notebook.
# .read starts the reading instructions; .option("header", True) says the first line holds the column names
# (without it, the names would become a data row); .csv(path) reads the file into a DataFrame called df.
df = (spark.read
      .option("header", True)
      .csv(path))

# Show each column's name and data type.
# Expect: every column is "string". Bronze keeps raw text on purpose; silver converts the types later.
df.printSchema()

# COMMAND ----------

# CELL 2 - Peek at a few rows and count them

# limit(5) is a TRANSFORMATION (Spark only plans it); display() is an ACTION (Spark runs now).
display(df.limit(5))

# count() is also an ACTION. Expect 99441, the same number as on the laptop with DuckDB.
print(df.count())

# COMMAND ----------

# CELL 3 - Load all 9 CSVs into bronze Delta tables

# Spark's built-in functions, with the standard short name F.
from pyspark.sql import functions as F

# The folder holding all 9 raw files. Written once, reused for every file.
LANDING = "/Volumes/workspace/bronze/landing/olist"

# A dictionary: short table name (key) -> source file name (value).
# Short names like "orders" are easier to use than the long file names.
tables = {
    "orders": "olist_orders_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "customers": "olist_customers_dataset.csv",
    "payments": "olist_order_payments_dataset.csv",
    "reviews": "olist_order_reviews_dataset.csv",
    "products": "olist_products_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
}

# Loop through each (table, file) pair, so one block of code loads all 9 tables.
for table, file in tables.items():
    df = (spark.read
          .option("header", True)          # first line = column names
          .option("multiLine", True)       # a value may span several lines (some review comments contain line breaks)
          .option("escape", '"')           # "" inside quoted text is a literal quote mark (keeps review text in one piece)
          .csv(f"{LANDING}/{file}")        # f-string builds the full path of the current file
          # Audit column: WHEN this row was loaded.
          .withColumn("_ingested_at", F.current_timestamp())
          # Lineage column: WHICH file this row came from. _metadata is a hidden column Spark provides for files.
          .withColumn("_source_file", F.col("_metadata.file_path")))
    # The underscore at the start of _ingested_at and _source_file marks columns WE added, not the source.

    (df.write
       .mode("overwrite")                     # replace the table if it exists -> safe to rerun (idempotent)
       .option("overwriteSchema", True)       # allow the columns to change on a rerun without an error
       .saveAsTable(f"workspace.bronze.{table}"))   # save as a Delta table: catalog.schema.table

    print(f"Loaded workspace.bronze.{table}")

# COMMAND ----------

# CELL 4 - Reconciliation: prove that no rows were lost or added

# The row counts measured on the laptop on Day 2 (the baseline).
expected = {
    "orders": 99441,
    "order_items": 112650,
    "customers": 99441,
    "payments": 103886,
    "reviews": 99224,
    "products": 32951,
    "sellers": 3095,
    "geolocation": 1000163,
    "category_translation": 71,
}

for table, exp in expected.items():
    actual = spark.table(f"workspace.bronze.{table}").count()     # rows that actually landed in bronze
    status = "OK" if actual == exp else "MISMATCH"                # flag any lost or extra rows
    # {table:22} pads the name to 22 characters; {exp:>9,} right-aligns the number with commas.
    print(f"{table:22} expected {exp:>9,}   bronze {actual:>9,}   {status}")

# Expect: 9 lines, all OK.
