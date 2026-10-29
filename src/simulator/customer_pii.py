# Databricks notebook source
# MAGIC %md
# MAGIC # 04_customer_pii - Day 7 (part 2): simulated customer data and GDPR tokenisation
# MAGIC Olist is already anonymised (no names or emails), so we **simulate** realistic personal data,
# MAGIC then protect it exactly as a real UK company would under UK GDPR.
# MAGIC
# MAGIC | Step | Builds |
# MAGIC | --- | --- |
# MAGIC | 1 | Install Faker (a fake-data library) |
# MAGIC | 2 | restricted schema + token vault table |
# MAGIC | 3 | restricted.customer_profiles_raw (simulated names, emails, phones) |
# MAGIC | 4 | bronze.customer_address_changes (simulated house moves, used for SCD Type 2 later) |
# MAGIC | 5 | Tokens for every name, email and phone, stored in the vault |
# MAGIC | 6 | silver.customer_profiles (tokens only, no personal data) |
# MAGIC | 7 | Checks: no personal data in silver, idempotent reruns, reconciliation |
# MAGIC
# MAGIC Run each cell from top to bottom with **Shift + Enter**.

# COMMAND ----------

# MAGIC %pip install faker==30.8.2

# COMMAND ----------

# CELL 1b - Restart Python so the newly installed library can be imported.
# Restarting clears all variables, which is why the imports come in the NEXT cell.
dbutils.library.restartPython()

# COMMAND ----------

# CELL 2 - Setup
import random  # Python's random-number tools
from datetime import timedelta  # lets us add days to a date

from faker import Faker  # library that generates realistic fake data
from pyspark.sql import functions as F

# Seeds make "random" results REPEATABLE: same seed -> same fake people every run.
# That keeps the pipeline idempotent and the numbers reproducible for your README.
Faker.seed(42)
random.seed(42)
fake = Faker("pt_BR")              # Brazilian-style names, cities and phone numbers (Olist is Brazilian)

print("Setup done")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 2 - Restricted schema and token vault

# COMMAND ----------

# MAGIC %sql
# MAGIC -- CELL 3 - A separate, locked-down schema for personal data.
# MAGIC -- Raw personal data and the token vault live ONLY here, never in bronze, silver or gold.
# MAGIC CREATE SCHEMA IF NOT EXISTS workspace.restricted;
# MAGIC
# MAGIC -- The token vault: maps each real value to a random token.
# MAGIC -- pii_type = 'name' / 'email' / 'phone'; pii_value = the real value; token = the random replacement.
# MAGIC CREATE TABLE IF NOT EXISTS workspace.restricted.token_vault (
# MAGIC   pii_type   STRING,
# MAGIC   pii_value  STRING,
# MAGIC   token      STRING,
# MAGIC   created_at TIMESTAMP
# MAGIC );

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 3 - Simulate customer profiles

# COMMAND ----------

# CELL 4 - Generate one fake name, email and phone for every real customer

# Every real person (customer_unique_id), sorted so the seed gives the same person the same fake data every run.
ids = [r.customer_unique_id for r in
       spark.table("workspace.silver.customers")
            .select("customer_unique_id").distinct()
            .orderBy("customer_unique_id")
            .collect()]                                  # collect() brings the rows to Python as a list

print("real customers:", len(ids))

rows = []
for i, cid in enumerate(ids):                            # enumerate gives a counter i alongside each id
    name = fake.name()
    # Adding the counter i guarantees every email is unique.
    email = f"{fake.user_name()}{i}@{fake.free_email_domain()}"
    phone = fake.phone_number()
    rows.append((cid, name, email, phone))

profiles_raw = (spark.createDataFrame(rows, "customer_unique_id STRING, full_name STRING, email STRING, phone STRING")
                .withColumn("_ingested_at", F.current_timestamp())
                .withColumn("_source", F.lit("simulator")))     # lineage: where this data came from

# Saved in the RESTRICTED schema because it contains personal data.
profiles_raw.write.mode("overwrite").option("overwriteSchema", True).saveAsTable("workspace.restricted.customer_profiles_raw")

print("restricted.customer_profiles_raw:", spark.table("workspace.restricted.customer_profiles_raw").count())
display(spark.table("workspace.restricted.customer_profiles_raw").limit(3))     # what raw PII looks like

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 4 - Simulate house moves (for SCD Type 2 on Day 10)

# COMMAND ----------

# CELL 5 - Some customers move city after their first order

# First order date for each real person: join customers (customer_id -> customer_unique_id) to orders.
first_orders = (spark.table("workspace.silver.customers")
    .join(spark.table("workspace.silver.orders"), on="customer_id", how="inner")
    .groupBy("customer_unique_id")
    .agg(F.min("order_purchase_timestamp").alias("first_order_at"))
    .orderBy("customer_unique_id"))

# About 5% of customers move. sample() with a seed picks the same customers every run.
movers = first_orders.sample(fraction=0.05, seed=42).collect()

changes = []
for r in movers:
    moves = random.choice([1, 1, 1, 2])               # most move once, some move twice
    moved_at = r.first_order_at
    for _ in range(moves):
        moved_at = moved_at + timedelta(days=random.randint(30, 400))    # a move 1-13 months later
        changes.append((r.customer_unique_id, fake.city().lower(), fake.estado_sigla(), moved_at))

address_changes = (spark.createDataFrame(changes,
                     "customer_unique_id STRING, new_city STRING, new_state STRING, effective_at TIMESTAMP")
                   .withColumn("_ingested_at", F.current_timestamp())
                   .withColumn("_source", F.lit("simulator")))

# A city and state alone do not identify a person, so this can live in bronze.
address_changes.write.mode("overwrite").option("overwriteSchema", True).saveAsTable("workspace.bronze.customer_address_changes")

print("customers who moved:", len(movers), "  move events:", len(changes))
display(address_changes.orderBy("customer_unique_id", "effective_at").limit(5))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 5 - Create tokens in the vault

# COMMAND ----------

# CELL 6 - Give every NEW name, email and phone a random token (idempotent)

prof = spark.table("workspace.restricted.customer_profiles_raw")

# Put all personal values into one long list: (type, value). unionByName stacks tables by column name.
values = (prof.select(F.lit("name").alias("pii_type"), F.col("full_name").alias("pii_value"))
          .unionByName(prof.select(F.lit("email").alias("pii_type"), F.col("email").alias("pii_value")))
          .unionByName(prof.select(F.lit("phone").alias("pii_type"), F.col("phone").alias("pii_value")))
          .distinct())

vault = spark.table("workspace.restricted.token_vault")

# LEFT ANTI JOIN = keep only values NOT already in the vault.
# This makes reruns safe: existing values keep their existing token; only new ones get a new token.
new_values = values.join(vault, on=["pii_type", "pii_value"], how="left_anti")

# IMPORTANT (lazy evaluation trap): count BEFORE writing. Spark recalculates a DataFrame each
# time you use it; after the write, these values ARE in the vault, so a later count would say 0.
n_new = new_values.count()

new_tokens = (new_values
              .withColumn("token", F.expr("uuid()"))            # a random ID with no link to the real value
              .withColumn("created_at", F.current_timestamp()))

new_tokens.write.mode("append").saveAsTable("workspace.restricted.token_vault")   # APPEND: never overwrite the vault

print("new tokens added:", n_new)
print("vault size:", spark.table("workspace.restricted.token_vault").count())

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 6 - Build silver.customer_profiles with tokens only

# COMMAND ----------

# CELL 7 - Replace every personal value with its token

vault = spark.table("workspace.restricted.token_vault")

def tokenise(df, column, pii_type):
    """Swap a personal column for its token column, using the vault."""
    mapping = (vault.filter(F.col("pii_type") == pii_type)
                    .select(F.col("pii_value").alias(column), F.col("token").alias(f"{column}_token")))
    return df.join(mapping, on=column, how="left").drop(column)    # add the token, remove the real value

silver_profiles = spark.table("workspace.restricted.customer_profiles_raw")
for column, pii_type in [("full_name", "name"), ("email", "email"), ("phone", "phone")]:
    silver_profiles = tokenise(silver_profiles, column, pii_type)

silver_profiles = (silver_profiles
                   .drop("_ingested_at")
                   .withColumn("_tokenised_at", F.current_timestamp()))

silver_profiles.write.mode("overwrite").option("overwriteSchema", True).saveAsTable("workspace.silver.customer_profiles")

print("silver.customer_profiles columns:", spark.table("workspace.silver.customer_profiles").columns)
display(spark.table("workspace.silver.customer_profiles").limit(3))     # tokens only

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 7 - Checks

# COMMAND ----------

# CELL 8 - Three checks that prove the design works

sp = spark.table("workspace.silver.customer_profiles")

# Check 1: no personal columns in silver
pii_columns = {"full_name", "email", "phone"}
leaked = pii_columns.intersection(set(sp.columns))
print("1. personal columns in silver:", leaked if leaked else "none  -> OK")

# Check 2: every value got a token (no NULL tokens)
missing = sp.filter(F.col("full_name_token").isNull() | F.col("email_token").isNull() | F.col("phone_token").isNull()).count()
print("2. rows with a missing token:", missing, " -> OK" if missing == 0 else " -> PROBLEM")

# Check 3: reconciliation - one silver profile per raw profile per real customer
raw_n = spark.table("workspace.restricted.customer_profiles_raw").count()
silver_n = sp.count()
customers_n = spark.table("workspace.silver.customers").select("customer_unique_id").distinct().count()
print(f"3. raw {raw_n:,} = silver {silver_n:,} = real customers {customers_n:,}",
      "-> OK" if raw_n == silver_n == customers_n else "-> MISMATCH")

# COMMAND ----------

# CELL 9 - Idempotency check: rerunning the token step must create ZERO new tokens

prof = spark.table("workspace.restricted.customer_profiles_raw")
values = (prof.select(F.lit("name").alias("pii_type"), F.col("full_name").alias("pii_value"))
          .unionByName(prof.select(F.lit("email").alias("pii_type"), F.col("email").alias("pii_value")))
          .unionByName(prof.select(F.lit("phone").alias("pii_type"), F.col("phone").alias("pii_value")))
          .distinct())
still_new = values.join(spark.table("workspace.restricted.token_vault"), on=["pii_type", "pii_value"], how="left_anti").count()
print("values without a token after rerun:", still_new, " -> OK (idempotent)" if still_new == 0 else " -> PROBLEM")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Access control (read only - for your understanding)
# MAGIC In a company, permissions are set on the schemas. Free Edition has only you as a user, so these are examples, not commands to run:
# MAGIC
# MAGIC ```
# MAGIC -- Analysts can read silver and gold, but never the restricted schema:
# MAGIC GRANT USE SCHEMA, SELECT ON SCHEMA workspace.silver TO `analysts`;
# MAGIC REVOKE ALL PRIVILEGES ON SCHEMA workspace.restricted FROM `analysts`;
# MAGIC
# MAGIC -- Only the data protection team can read the vault:
# MAGIC GRANT USE SCHEMA, SELECT ON SCHEMA workspace.restricted TO `data_protection`;
# MAGIC ```
# MAGIC
# MAGIC **Right to erasure (UK GDPR):** to "forget" a customer, delete their rows from `restricted.customer_profiles_raw` and their values from `restricted.token_vault`.
# MAGIC The tokens left in silver and gold then point to nothing, so the person can no longer be identified, without rebuilding any other table.
