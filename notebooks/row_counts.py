import duckdb
import glob
import os

files = sorted(glob.glob("data/raw/*.csv"))
print("Files found:", len(files))

for f in files:
    count = duckdb.sql(f"SELECT COUNT(*) FROM '{f}'").fetchone()[0]
    name = os.path.basename(f)
    print(name, count)

print(duckdb.sql("""
    SELECT
        COUNT(*)                           AS total_rows,
        COUNT(DISTINCT customer_id)        AS distinct_customer_ids,
        COUNT(DISTINCT customer_unique_id) AS distinct_real_people
    FROM 'data/raw/olist_customers_dataset.csv'
"""))