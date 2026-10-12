import duckdb

# Count how many orders are in the Olist orders file
result = duckdb.sql("SELECT COUNT(*) AS total_orders FROM 'data/raw/olist_orders_dataset.csv'")
print(result)