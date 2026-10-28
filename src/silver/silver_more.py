# Databricks notebook source
# MAGIC %md
# MAGIC # 03_silver_more - Day 7 (part 1): the remaining silver tables
# MAGIC Run each cell from top to bottom with **Shift + Enter**. Read the comments before running each cell, and predict the result.
# MAGIC
# MAGIC | Step | Builds |
# MAGIC | --- | --- |
# MAGIC | 1 | silver.payments + silver.payments_quarantine |
# MAGIC | 2 | silver.products (with English category names) |
# MAGIC | 3 | silver.sellers |
# MAGIC | 4 | silver.geolocation (one row per postcode prefix) + quarantine |
# MAGIC | 5 | Reconciliation for all 4 tables |

# COMMAND ----------

# CELL 0 - Setup
# Load Spark's built-in functions as F. Every new notebook needs this again.
from pyspark.sql import functions as F

print("Setup done")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 1 - silver.payments

# COMMAND ----------

# CELL 1 - Type payments, apply 3 quality rules, split into silver and quarantine

pay_bronze = spark.table("workspace.bronze.payments")   # silver is always built from bronze

pay = (pay_bronze
    # 1st, 2nd, 3rd payment for the order -> a whole number
    .withColumn("payment_sequential", F.expr("try_cast(payment_sequential AS INT)"))
    # number of instalments -> a whole number
    .withColumn("payment_installments", F.expr("try_cast(payment_installments AS INT)"))
    # money is ALWAYS an exact DECIMAL, never DOUBLE
    .withColumn("payment_value", F.expr("try_cast(payment_value AS DECIMAL(10,2))"))
    # clean the text so 'Credit_Card ' and 'credit_card' are the same value
    .withColumn("payment_type", F.lower(F.trim(F.col("payment_type")))))

# Quality rules (IF / ELSE IF / ELSE). A value of 0 is allowed (fully voucher-paid orders).
pay_dq = (F.when(F.col("payment_value").isNull(), "value_missing_or_invalid")   # silent cast failure
           .when(F.col("payment_value") < 0, "value_negative")                 # validity rule
           .when(F.col("payment_type") == "not_defined", "type_not_defined")   # unknown method
           .otherwise(None))                                                   # NULL = clean row

pay_checked = pay.withColumn("dq_issue", pay_dq)
pay_good = pay_checked.filter(F.col("dq_issue").isNull()).drop("dq_issue")
pay_bad = (pay_checked.filter(F.col("dq_issue").isNotNull())
           .withColumn("_quarantined_at", F.current_timestamp()))              # when it was caught

pay_good.write.mode("overwrite").option("overwriteSchema", True).saveAsTable("workspace.silver.payments")
pay_bad.write.mode("overwrite").option("overwriteSchema", True).saveAsTable("workspace.silver.payments_quarantine")

print("silver.payments:", pay_good.count(), "  quarantine:", pay_bad.count())

# How customers pay (a useful business fact)
display(pay_good.groupBy("payment_type").count().orderBy(F.desc("count")))

# Which rows were set aside, and why
display(pay_bad.select("order_id", "payment_type", "payment_value", "dq_issue"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 2 - silver.products

# COMMAND ----------

# CELL 2 - Clean the category translation table
# The translation CSV can start with an invisible "byte order mark" (BOM) character,
# which sneaks into the first column's NAME. Renaming the columns by POSITION avoids that problem.

tr_bronze = spark.table("workspace.bronze.category_translation")
tr_cols = tr_bronze.columns                     # e.g. [product_category_name, product_category_name_english, _ingested_at, _source_file]

translation = (tr_bronze
    .toDF("product_category_name", "product_category_name_english", *tr_cols[2:])   # rename by position
    .withColumn("product_category_name", F.lower(F.trim(F.col("product_category_name"))))
    .withColumn("product_category_name_english", F.lower(F.trim(F.col("product_category_name_english"))))
    .select("product_category_name", "product_category_name_english"))              # keep only what we need

print("categories in translation table:", translation.count())

# COMMAND ----------

# CELL 3 - Type products, fix the source's spelling mistakes, add English category names

prod_bronze = spark.table("workspace.bronze.products")

products = (prod_bronze
    .withColumn("product_category_name", F.lower(F.trim(F.col("product_category_name"))))
    # The source file misspells "length" as "lenght". Silver fixes the names (and data_model.md documents it).
    .withColumnRenamed("product_name_lenght", "product_name_length")
    .withColumnRenamed("product_description_lenght", "product_description_length")
    # Counts and measurements -> whole numbers
    .withColumn("product_name_length", F.expr("try_cast(product_name_length AS INT)"))
    .withColumn("product_description_length", F.expr("try_cast(product_description_length AS INT)"))
    .withColumn("product_photos_qty", F.expr("try_cast(product_photos_qty AS INT)"))
    .withColumn("product_weight_g", F.expr("try_cast(product_weight_g AS INT)"))
    .withColumn("product_length_cm", F.expr("try_cast(product_length_cm AS INT)"))
    .withColumn("product_height_cm", F.expr("try_cast(product_height_cm AS INT)"))
    .withColumn("product_width_cm", F.expr("try_cast(product_width_cm AS INT)")))

# LEFT JOIN keeps EVERY product, even if its category has no translation (no rows lost).
products = products.join(translation, on="product_category_name", how="left")

# English name if we have one, otherwise the Portuguese name, otherwise 'unknown'.
products = products.withColumn(
    "category_english",
    F.coalesce(F.col("product_category_name_english"), F.col("product_category_name"), F.lit("unknown"))
).drop("product_category_name_english")

# A FLAG, not quarantine: products are a DIMENSION. Removing a product would break every
# order item that points to it (orphans). So we keep the row and mark the suspicious value.
products = products.withColumn(
    "is_weight_suspect",
    F.col("product_weight_g").isNull() | (F.col("product_weight_g") <= 0)
)

products.write.mode("overwrite").option("overwriteSchema", True).saveAsTable("workspace.silver.products")

print("silver.products:", products.count())
print("products with no category at all:", products.filter(F.col("product_category_name").isNull()).count())
print("categories with no English translation:",
      products.filter(F.col("product_category_name").isNotNull() &
                      (F.col("category_english") == F.col("product_category_name"))).select("product_category_name").distinct().count())
print("products flagged weight suspect:", products.filter("is_weight_suspect").count())
display(products.groupBy("category_english").count().orderBy(F.desc("count")).limit(10))   # top 10 categories

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 3 - silver.sellers

# COMMAND ----------

# CELL 4 - Clean seller location text (same rules as customers on Day 6)

sellers = (spark.table("workspace.bronze.sellers")
    .withColumn("seller_city", F.lower(F.trim(F.col("seller_city"))))          # ' Sao Paulo' -> 'sao paulo'
    .withColumn("seller_state", F.upper(F.trim(F.col("seller_state"))))        # state codes in capitals
    .withColumn("seller_zip_code_prefix", F.lpad(F.trim(F.col("seller_zip_code_prefix")), 5, "0")))  # 1151 -> 01151, kept as text

sellers.write.mode("overwrite").option("overwriteSchema", True).saveAsTable("workspace.silver.sellers")

print("silver.sellers:", sellers.count())
display(sellers.groupBy("seller_state").count().orderBy(F.desc("count")).limit(5))   # where sellers are based

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 4 - silver.geolocation

# COMMAND ----------

# CELL 5 - Type coordinates and quarantine points outside Brazil

geo_bronze = spark.table("workspace.bronze.geolocation")

geo = (geo_bronze
    .withColumn("geolocation_zip_code_prefix", F.lpad(F.trim(F.col("geolocation_zip_code_prefix")), 5, "0"))
    # Coordinates are measurements (not money), so DOUBLE is fine here.
    .withColumn("geolocation_lat", F.expr("try_cast(geolocation_lat AS DOUBLE)"))
    .withColumn("geolocation_lng", F.expr("try_cast(geolocation_lng AS DOUBLE)"))
    .withColumn("geolocation_city", F.lower(F.trim(F.col("geolocation_city"))))
    .withColumn("geolocation_state", F.upper(F.trim(F.col("geolocation_state")))))

# Brazil lies roughly between latitude -34 and +6, and longitude -74 and -34.
# A point outside that box is a data error (e.g. a typo in the coordinates).
inside_brazil = (F.col("geolocation_lat").between(-34, 6) & F.col("geolocation_lng").between(-74, -34))

geo_valid = geo.filter(inside_brazil)
geo_bad = (geo.filter(~inside_brazil | F.col("geolocation_lat").isNull() | F.col("geolocation_lng").isNull())
           .withColumn("dq_issue", F.lit("outside_brazil_or_invalid"))
           .withColumn("_quarantined_at", F.current_timestamp()))

geo_bad.write.mode("overwrite").option("overwriteSchema", True).saveAsTable("workspace.silver.geolocation_quarantine")

print("valid points:", geo_valid.count(), "  quarantined points:", geo_bad.count())

# COMMAND ----------

# CELL 6 - One row per postcode prefix (removes the 1 million row fan-out risk)
# Many map points share a postcode prefix. Joining customers to this table as-is would
# duplicate customers (fan-out). So we AGGREGATE: one row per prefix, with the average point.

geo_silver = (geo_valid
    .groupBy("geolocation_zip_code_prefix")
    .agg(
        F.round(F.avg("geolocation_lat"), 6).alias("lat"),        # centre point of the prefix
        F.round(F.avg("geolocation_lng"), 6).alias("lng"),
        F.mode("geolocation_city").alias("city"),                 # most common city name for the prefix
        F.mode("geolocation_state").alias("state"),               # most common state for the prefix
        F.count("*").alias("points_averaged"),                    # how many raw points were combined
    )
    .withColumnRenamed("geolocation_zip_code_prefix", "zip_code_prefix"))

geo_silver.write.mode("overwrite").option("overwriteSchema", True).saveAsTable("workspace.silver.geolocation")

print("silver.geolocation rows (one per postcode prefix):", geo_silver.count())
display(geo_silver.orderBy(F.desc("points_averaged")).limit(5))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 5 - Reconcile

# COMMAND ----------

# CELL 7 - Prove that no rows were lost or created

def n(table_name):
    """Count the rows in any table."""
    return spark.table(table_name).count()

checks = [
    ("payments", n("workspace.bronze.payments"),
     n("workspace.silver.payments") + n("workspace.silver.payments_quarantine")),
    ("products", n("workspace.bronze.products"), n("workspace.silver.products")),
    ("sellers", n("workspace.bronze.sellers"), n("workspace.silver.sellers")),
]
for name, bronze_n, silver_n in checks:
    print(f"{name:12} bronze {bronze_n:>9,}  silver+quarantine {silver_n:>9,}  {'OK' if bronze_n == silver_n else 'MISMATCH'}")

# Geolocation: bronze points = valid points + quarantined points; silver is then aggregated on purpose.
gb = n("workspace.bronze.geolocation")
gq = n("workspace.silver.geolocation_quarantine")
gv = geo_valid.count()
print(f"{'geolocation':12} bronze {gb:>9,}  valid {gv:>9,} + quarantine {gq:>5,}  {'OK' if gb == gv + gq else 'MISMATCH'}"
      f"  -> aggregated to {n('workspace.silver.geolocation'):,} postcode prefixes")
