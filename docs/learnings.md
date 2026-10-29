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
- Found: dbt build PASS=56 WARN=1 ERROR=0 (the known 15 quarantined-order items); dim_customer has 102,092 versions (96,082 current + 6,010 historical, all simulated moves); most versions for one customer is 3 (sao paulo, then martins MA, then peixoto DF); every customer has exactly one current row and no versions overlap; fact_sales still has 112,635 rows and every sale has a customer_key; customer e2889baccec81ed3bed4d66c1c675cb2 bought on 2017-05-23 in eldorado do sul (version 1), moved on 2017-11-02, and their 2017-11-27 sale links to mendonça do sul (version 2).
- Problems: current rows were 96,082, not the expected 96,096, because the 14 customers whose only order was quarantined have no first-order address (correct, not a bug); the customer with the most versions had no sales after moving (their moves came after the data ends), so I searched for a customer with sales in two versions to prove the as-of join.

## Day 11 – Reconciliation report and audit tests
- Built: an audit layer in dbt (workspace.audit) with reconciliation_report, one row per table showing bronze, silver, quarantine, removed-on-purpose and gold row counts plus a pass/fail check; 3 singular tests (all checks passed, the 15 excluded items match quarantine, the 14 missing customers match quarantine); a dbt docs overview page; all 10 bronze tables and 4 quarantine tables declared as sources.
- Learned: a reconciliation report is a table that proves, with counts, that every raw row was kept, set aside, or removed on purpose for a known reason, so nothing disappears silently. Tests should fail the build when layers drift, because a number that changes without a reason is a bug even if no query crashes; failing early stops wrong numbers reaching a dashboard. Comparing two lists with EXCEPT checks which rows differ, not just how many. dbt docs generate builds a documentation site with descriptions and a lineage graph.
- Why: anyone can say "the data is correct"; a reconciliation report and tests that run on every build prove it, and explain every gap in one sentence.
- Found: dbt build PASS=60 WARN=1 ERROR=0 (17 models, 44 tests; the warning is the known 15 quarantined-order items); both known-gap tests pass, so the 15 excluded items and 14 missing customers are exactly the expected ones; all 8 tables reconcile; 14 orders, 3 payments and 42 map points are quarantined; 551 duplicate reviews, 15 items of quarantined orders and 14 customers with only quarantined orders are removed on purpose; revenue goes from 13,591,643.70 in silver to 13,589,748.34 in gold (minus 1,895.36 for the 15 excluded items) and 13,220,248.93 for delivered orders, versus 14,209,115.34 if payments had caused fan-out.
- Problems: the first dbt build started before the new files were saved, so it ran only the Day 10 project (same timing issue as Day 8); the next build only ran assert_reconciliation_all_passed because the two known-gap tests did not exist yet.
- Interview line: "In my data engineering work at NISG I saw that people only use numbers they can trust, so in this project I made trust provable: a reconciliation report traces every table from bronze to gold, and the build fails the moment any layer drifts."

## Day 12 – Incremental fact_sales and a Databricks job
- Built (Part A): changed gold.fact_sales from a table rebuilt every run into an incremental model (merge on sales_key, 3-day lookback on purchased_at); added purchased_at to fact_sales so the filter has a real timestamp to use.
- Built (Part C): a Databricks job, olist_lakehouse_pipeline, that runs the whole pipeline in order: setup, bronze_ingest, then build_silver and silver_more side by side, customer_pii after build_silver, and dbt_build (dbt deps + dbt build from GitHub) last. All tasks run on serverless; the daily 06:00 schedule is paused. Documented in jobs/olist_lakehouse_pipeline.yml and the Orchestration section of docs/data_model.md.
- Learned (incremental): a full refresh throws the table away and rebuilds every row from scratch (slow but always complete), while an incremental run keeps the table and only processes new rows (fast). is_incremental() is true only when the table already exists and the run is not --full-refresh, so the first build and any --full-refresh load everything. merge means "update the rows that already exist, insert the ones that don't", and unique_key (sales_key) is how dbt knows two rows are the same sale, so rerunning never creates duplicates. The lookback window (3 days before the newest sale already loaded) re-processes the most recent rows in case they arrived late or changed, and merge makes that safe.
- Learned (job): a job is a list of tasks with arrows between them; a task starts only when every task it depends on has succeeded, and tasks with no arrow between them run at the same time. A dbt task can read the dbt project straight from GitHub and needs no token in any file, because Databricks connects with the job's own identity. A trigger that fires when a table changes would loop forever if the job itself writes that table.
- Why: on a real, growing business the fact table gets bigger every day; rebuilding millions of rows nightly wastes time and money, so only the new slice is processed. A scheduled full refresh still catches changes to old rows (like a late status update) that the lookback window cannot see. A job turns notebooks and dbt that I ran by hand into one pipeline that always runs in the right order.
- Found: the full refresh built 112,635 rows; I deleted the last month (6,566 rows, leaving 106,069); the next normal (incremental) run brought it back to 112,635, and all tests passed, including the reconciliation and known-gap tests. The job's first full run took 4m 41s (setup 16s, bronze_ingest 32s, build_silver 39s, silver_more 38s, customer_pii 38s, dbt_build 2m 31s) and read 17.3 million rows and wrote 2.6 million.
- Problems:
  - ran dbt from the repo root, so it could not find dbt_project.yml (fixed by running `cd dbt` first);
  - typed SQL into PowerShell, which does not understand SQL (fixed by running SQL in the Databricks SQL Editor);
  - checked the row count before the incremental build had finished, so it still showed 106,069 (fixed by counting again after `Done.`);
  - put the GitHub URL in the dbt task's project directory box (fixed: the URL goes in the Git source settings, and the project directory is just `dbt`);
  - hidden spaces before "dbt" in the dbt command boxes made the commands fail (fixed by deleting the spaces so each command starts with `dbt`).

## Day 13 – GitHub Actions CI
- Built: a GitHub Actions workflow (`.github/workflows/ci.yml`) that runs on every push to main and every pull request: ruff for Python, sqlfluff for SQL, dbt deps + dbt parse with a fake profile, and a separate gitleaks job that scans for leaked secrets; pinned tool versions in requirements-ci.txt; a CI badge in the README.
- Learned: CI means a fresh machine checks every change automatically, so a broken file is caught in minutes on GitHub, not later in a Databricks run. ruff checks Python for bugs and style; sqlfluff checks SQL style and renders the Jinja itself, so it needs no database; dbt parse checks the whole dbt project (YAML, ref(), source(), configs) without connecting; gitleaks searches the code and all git history for anything that looks like a password or token. A linter rule is a tool, not a law: when a rule fights a real pattern (imports after %pip in a notebook, `select *` import CTEs, column names like year and state), switching it off with a written reason is better than bending the code.
- Why: CI must never hold my Databricks token, so it uses a dummy profile; dbt parse does not connect, so fake values are enough, and there is no secret that could leak through logs or pull requests.
- Found: ruff fixed 11 issues (missing final newlines, import order) and sqlfluff fixed 124 layout issues; I switched off 2 ruff rules (E402, E501) and 4 sqlfluff rules (AL03, RF04, AM04, ST06) with comments; comparing the rendered SQL of all 23 models and tests before and after proved the fixes changed formatting only, apart from added table aliases and an explicit `asc`. Both linters now pass with zero errors.
- Problems: `.gitignore` ignored every file called profiles.yml, which would also have hidden the fake CI profile (fixed with `!ci/profiles.yml`); sqlfluff could not render `dbt_utils.generate_surrogate_key` without a database (fixed with a small stand-in in `dbt/sqlfluff_libs/dbt_utils.py` that only the linter uses).
- Interview line: "Every push to my lakehouse repo runs CI that lints the Python and SQL, parses the whole dbt project and scans the history for secrets, all without a single real credential, because dbt parse runs against a dummy profile."
