# Databricks notebook source
path = "/Volumes/workspace/bronze/landing/olist/olist_orders_dataset.csv"

df = (spark.read
      .option("header", True)
      .csv(path))

df.printSchema()

# COMMAND ----------

display(df.limit(5))
print(df.count())

# COMMAND ----------

from pyspark.sql import functions as F

LANDING = "/Volumes/workspace/bronze/landing/olist"

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

for table, file in tables.items():
    df = (spark.read
          .option("header", True)
          .option("multiLine", True)
          .option("escape", '"')
          .csv(f"{LANDING}/{file}")
          .withColumn("_ingested_at", F.current_timestamp())
          .withColumn("_source_file", F.col("_metadata.file_path")))

    (df.write
       .mode("overwrite")
       .option("overwriteSchema", True)
       .saveAsTable(f"workspace.bronze.{table}"))

    print(f"Loaded workspace.bronze.{table}")

# COMMAND ----------

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
    actual = spark.table(f"workspace.bronze.{table}").count()
    status = "OK" if actual == exp else "MISMATCH"
    print(f"{table:22} expected {exp:>9,}   bronze {actual:>9,}   {status}")