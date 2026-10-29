import duckdb

ORDERS = "'data/raw/olist_orders_dataset.csv'"

# Check 1: how many orders are in each status?
print(duckdb.sql(f"""
    SELECT order_status, COUNT(*) AS orders
    FROM {ORDERS}
    GROUP BY order_status
    ORDER BY orders DESC
"""))

# Check 2: delivered orders that have no customer delivery date (broken data)
print(duckdb.sql(f"""
    SELECT COUNT(*) AS delivered_but_no_date
    FROM {ORDERS}
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NULL
"""))

# Check 3: canceled orders that still have a delivery date (contradiction)
print(duckdb.sql(f"""
    SELECT COUNT(*) AS canceled_but_delivered
    FROM {ORDERS}
    WHERE order_status = 'canceled'
      AND order_delivered_customer_date IS NOT NULL
"""))

# Check 4: orders delivered before they were purchased (impossible)
print(duckdb.sql(f"""
    SELECT COUNT(*) AS delivered_before_purchase
    FROM {ORDERS}
    WHERE order_delivered_customer_date < order_purchase_timestamp
"""))

# Check 5: the 10 most expensive order items (check for silly prices)
print(duckdb.sql("""
    SELECT order_id, product_id, price, freight_value
    FROM 'data/raw/olist_order_items_dataset.csv'
    ORDER BY price DESC
    LIMIT 10
"""))
