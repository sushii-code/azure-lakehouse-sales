from pathlib import Path

import duckdb

# Find the project folder from this script's own location
PROJECT = Path(__file__).resolve().parent.parent
RAW = PROJECT / "data" / "raw"

ORDERS = f"'{(RAW / 'olist_orders_dataset.csv').as_posix()}'"
CUSTOMERS = f"'{(RAW / 'olist_customers_dataset.csv').as_posix()}'"

# Check 1: is order_id a true primary key (unique and never empty)?
print(duckdb.sql(f"""
    SELECT
        COUNT(*)                 AS total_rows,
        COUNT(DISTINCT order_id) AS distinct_order_ids,
        COUNT(order_id)          AS non_empty_order_ids
    FROM {ORDERS}
"""))

# Check 2: how many real people ordered more than once?
print(duckdb.sql(f"""
    SELECT COUNT(*) AS repeat_customers
    FROM (
        SELECT customer_unique_id, COUNT(*) AS orders_per_person
        FROM {CUSTOMERS}
        GROUP BY customer_unique_id
        HAVING COUNT(*) > 1
    )
"""))
