# Learnings

## Day 1 
- Built: set up Python, Git, Databricks Free Edition; pushed the starter repo; downloaded Olist; ran my first DuckDB query (99,441 orders).
- Learned: a lakehouse has bronze (raw), silver (clean) and gold (business-ready) layers; SELECT, FROM, DISTINCT.
- Problems: the repo was unzipped one level too deep, so I fixed the folder structure and re-pushed; PowerShell blocked the venv activate script, so I changed the execution policy.

## Day 2 
- Built: count_one.py (counted 2 tables by hand) and row_counts.py (a loop that counts all 9 Olist tables automatically); documented row counts, grain and findings in docs/data_model.md.
- Learned: COUNT(*) counts all rows in a table; COUNT(DISTINCT x) counts each different value once; a for loop repeats code for each item in a list; relative paths start from the terminal's folder, not the script's folder.
- Why: row counts are my baseline for reconciliation later; automating with a loop scales to any number of tables.
- Found: 99,441 customer IDs but only 96,096 real people, so 3,345 orders came from repeat customers. Gold must use customer_unique_id.
- Problems: "No files found" and "can't open file" because the terminal was in the outer folder (fixed with cd); NameError because files was used before it was created (fixed by putting lines in the right order).

## Day 3 
- Built: explore_orders.py with 5 data-quality checks on Olist orders and items.
- Learned: WHERE filters rows; AND combines conditions; IS NULL / IS NOT NULL test for missing values (never = NULL); ORDER BY ... DESC with LIMIT finds extremes; GROUP BY counts per group.
- Why: finding broken rows before cleaning gives the silver layer a clear specification.
- Found: 8 delivered orders with no delivery date, 6 canceled orders with a delivery date, 0 impossible dates; only delivered orders should count as sales.

## Day 4 
- Built: explore_keys.py (primary key check, repeat customers) and explore_joins.py (orphan check, fan-out check). Made scripts find data from their own location using pathlib, so they run from any folder.
- Learned: primary and foreign keys; GROUP BY with COUNT; HAVING filters groups (WHERE filters rows); subqueries; INNER vs LEFT JOIN; anti join (LEFT JOIN + IS NULL) finds orphans; fan-out (joining to a many-rows table duplicates rows and inflates sums).
- Why: joins can silently lose rows (orphans) or duplicate rows (fan-out); checking both before building gold keeps the numbers right.
- Found: order_id is a valid primary key; 2,997 repeat customers; fan-out inflated revenue by 617,471.64 (about 4.5%) when joining payments.

## Day 5 
- Built: Unity Catalog schemas (bronze, silver, gold) and a landing volume; PySpark notebook loading 9 CSVs into bronze Delta tables with _ingested_at and _source_file; reconciliation check (all 9 tables OK).
- Learned: Spark driver/executors/partitions; DataFrames; transformations vs actions and lazy evaluation; Delta tables; catalog.schema.table naming; volumes; dbutils.fs (ls, mv); recursion to search folders.
- Why: bronze keeps an exact, auditable copy of the source; reconciliation proves nothing was lost.
- Problems: uploaded the whole project folder instead of just the CSVs (fixed by renaming with dbutils.fs.mv and uploading the missing file); rerunning a move failed because the file had already moved (moves are not idempotent).

## Day 6 
- Built: notebooks/build_silver.ipynb creating silver.orders, silver.order_items, silver.customers and silver.reviews from bronze, plus quarantine tables for orders and items; reconciliation for all tables; documented results in docs/data_model.md.
- Learned: F.when / .otherwise for rule labels; try_to_timestamp and try_cast (return NULL instead of failing, so failures must be counted); DECIMAL(10,2) for money because DOUBLE drifts; lpad to keep postcode leading zeros; window functions (partitionBy + orderBy + ROW_NUMBER) to keep one row per group.
- Why: silver gives gold clean, correctly typed data; quarantine keeps bad rows with a reason instead of deleting them; one review per order prevents fan-out when gold joins reviews to orders.
- Found: 0 failed date conversions; 14 orders quarantined (delivered_no_date, canceled_with_delivery); 551 duplicate reviews removed (99,224 to 98,673); 2,965 orders with no delivery date were never delivered, so empty is correct there; bronze = silver + quarantine for orders (99,441 = 99,427 + 14), order_items (112,650) and customers (99,441).

## Day 7 – Silver part 2 and personal data
- Built: silver payments, products, sellers and geolocation; simulated customer profiles and house moves with Faker; a restricted schema, token vault and tokenised silver.customer_profiles.
- Learned: flag vs quarantine for dimensions; fixing source typos; renaming columns by position (BOM); aggregating to one row per key to stop fan-out; valid-range checks; synthetic data and seeds; PII and quasi-identifiers; masking vs hashing vs encryption vs tokenisation; left anti join; the lazy evaluation trap; GRANT and REVOKE; right to erasure.
- Why: silver must be complete and trustworthy, and personal data must never reach analysts.
- Found: 42 geolocation points outside Brazil; 19,010 postcode prefixes; 233,661 tokens; 0 personal columns in silver; reruns create 0 tokens.
- Problems: Faker was not found because the restart and the import ran together (fixed by installing first, then importing in a separate cell); my translation check counted categories spelled the same in both languages as untranslated (fixed to use a has_translation flag).
