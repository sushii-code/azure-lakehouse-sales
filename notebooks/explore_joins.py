from pathlib import Path

import duckdb

PROJECT = Path(__file__).resolve().parent.parent
RAW = PROJECT / "data" / "raw"

def csv(name):
    return f"'{(RAW / name).as_posix()}'"

ORDERS = csv("olist_orders_dataset.csv")
ITEMS = csv("olist_order_items_dataset.csv")
PAYMENTS = csv("olist_order_payments_dataset.csv")

# Check 1: items that point to an order that does not exist (orphans)
print(duckdb.sql(f"""
    SELECT COUNT(*) AS orphan_items
    FROM {ITEMS} AS i
    LEFT JOIN {ORDERS} AS o
        ON i.order_id = o.order_id
    WHERE o.order_id IS NULL
"""))

# Check 2: fan-out - total item revenue before and after joining payments
print(duckdb.sql(f"""
    SELECT
        (SELECT ROUND(SUM(price), 2) FROM {ITEMS}) AS true_revenue,
        (SELECT ROUND(SUM(i.price), 2)
         FROM {ITEMS} AS i
         JOIN {PAYMENTS} AS p ON i.order_id = p.order_id) AS revenue_after_join
"""))
