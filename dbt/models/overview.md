{% docs __overview__ %}

# azure-lakehouse-sales

A medallion lakehouse on Databricks (Unity Catalog, catalog `workspace`) built from the Olist
Brazilian e-commerce dataset, with dbt for the staging, gold and audit layers.

## Layers

| Layer | Schema | Built by | What it holds |
| --- | --- | --- | --- |
| Bronze | `workspace.bronze` | PySpark notebooks | Raw files exactly as received (all text) plus `_ingested_at` and `_source_file` |
| Silver | `workspace.silver` | PySpark notebooks | Cleaned, typed, deduplicated tables; broken rows go to `*_quarantine` tables with a reason |
| Restricted | `workspace.restricted` | PySpark notebooks | Simulated personal data and the token vault (never read by dbt) |
| Staging | `workspace.staging` | dbt views | One `stg_` view per source table with clear column names |
| Gold | `workspace.gold` | dbt tables | Star schema: `fact_sales` (one row per order item), `fct_orders` (one row per order), `dim_date`, `dim_product`, `dim_seller`, `dim_customer` (SCD Type 2) |
| Audit | `workspace.audit` | dbt tables | `reconciliation_report`: bronze to silver to gold row counts per table, with a pass/fail check |

## Audit layer

`audit.reconciliation_report` has one row per table (orders, order_items, payments, customers,
reviews, products, sellers, geolocation). It shows how many rows are in bronze, silver,
quarantine and gold, how many were removed on purpose, and whether the numbers add up
(`check_passed`). Singular tests fail the build if any check fails or if a known gap
(15 order items of quarantined orders, 14 customers whose only order was quarantined)
contains anything other than the expected rows.

{% enddocs %}
