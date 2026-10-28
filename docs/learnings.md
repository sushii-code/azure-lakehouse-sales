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

## Day 8 – dbt setup and staging models
- Built: a dbt project connected to Databricks (profile outside the repo, token read from an environment variable); a generate_schema_name macro so models land in workspace.staging and workspace.gold; sources for the 9 silver tables; 9 staging views with clear column names; 19 data tests.
- Learned: profiles.yml vs dbt_project.yml; env_var() keeps secrets out of files; sources vs ref; views for staging and tables for marts; how dbt builds schema names and how to override it; generic tests (unique, not_null, accepted_values, relationships); severity: warn vs error; dbt debug, dbt run, dbt test and dbt build.
- Why: staging gives every later model one clean, consistently named place to read from, and tests catch broken keys automatically on every run instead of by hand.
- Found: 9 views built; 27 of 28 steps passed with 0 errors; 15 order items point to the 14 orders quarantined in silver (relationship test warns, as designed).
- Problems: the first dbt debug stopped with KeyboardInterrupt because the run was interrupted while dbt was still loading (fixed by rerunning and waiting); dbt run ran before the model files were saved, so it found nothing to build and every test failed with TABLE_OR_VIEW_NOT_FOUND (fixed by building the models first, then testing).

## Day 9 – Gold star schema
- Built: dbt_utils package (1.4.1); gold tables dim_date, dim_product, dim_seller, fact_sales (one row per order item) and fct_orders (one row per order); 15 new tests including relationships between facts and dimensions and a singular reconciliation test.
- Learned: dbt packages and dbt deps; surrogate keys with generate_surrogate_key; a date spine with sequence + explode; INT yyyymmdd date keys; inner vs left joins as a deliberate design choice; aggregating to one row per key before joining to stop fan-out; singular tests (a query that fails if it returns rows); dbt build runs models and tests in dependency order.
- Why: a star schema with one clear grain per fact lets every number add up correctly, and the tests prove the facts link to real dimension rows and agree with each other.
- Found: fact_sales 112,635 rows (15 items of quarantined orders excluded); fct_orders 99,427 rows; item revenue 13,589,748.34, of which 13,220,248.93 from delivered orders; all 15 gold tests passed, including the reconciliation between the two facts.
- Problems: dbt build failed with "found only 0 package(s) installed" because dbt deps had not been run yet (fixed by running dbt deps first, then dbt build).

## Day 10 – SCD Type 2 customer dimension
- Built: a bronze source and stg_customer_address_changes; dim_customer as an event-based SCD Type 2 dimension (first-order address + simulated moves, with valid_from, valid_to, is_current, version_number and tokenised personal data); customer_key added to fact_sales with an as-of join; 7 new tests including two singular SCD tests.
- Learned: SCD Type 1 vs Type 2; event-based history vs dbt snapshots; UNION ALL to stack events; ROW_NUMBER to pick the first order and to remove same-time duplicates; LEAD to set valid_to and LAG to check for overlaps; ordering by event time handles late-arriving data; as-of (range) joins; Type 1 attributes inside a Type 2 dimension.
- Why: regional sales for past periods must stay correct after customers move, so each sale must link to the address valid at purchase time, not the latest one.
- Found: dim_customer has 102,092 rows (96,082 current + 6,010 moves); every customer has exactly one current row and no versions overlap; fact_sales still has 112,635 rows and every sale has a customer_key; a customer who moved on 2017-11-02 has a May 2017 sale linked to the old city and a November 2017 sale linked to the new one.
- Problems: current rows were 96,082, not the expected 96,096, because the 14 customers whose only order was quarantined have no first-order address (correct, not a bug); the customer with the most versions had no sales after moving (their moves came after the data ends), so I searched for a customer with sales in two versions to prove the as-of join.
