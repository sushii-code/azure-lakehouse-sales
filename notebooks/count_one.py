import duckdb

#count the rows in the order items file
result = duckdb.sql("SELECT COUNT(*) FROM 'data/raw/olist_order_items_dataset.csv'")
print(result)
