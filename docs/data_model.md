# Data model

This document describes the source data, the target star schema, and the design decisions behind it.

## Source tables (Olist)

Row counts profiled on 17 October with DuckDB (`notebooks/row_counts.py`).

| Table | Key(s) | Rows | One row means (grain) | Notes |
| --- | --- | --- | --- | --- |
| orders | order_id | 99,441 | one order | Status plus purchase, approval and delivery timestamps |
| order_items | order_id + order_item_id | 112,650 | one item within an order | More rows than orders: one order can contain several items |
| customers | customer_id | 99,441 | one customer ID (a new one per order) | customer_id is new on every order; customer_unique_id is the real person |
| payments | order_id + payment_sequential | 103,886 | one payment method used for an order | More rows than orders: one order can be paid in several ways (e.g. card plus voucher) |
| reviews | review_id | 99,224 | one review | Comments can contain line breaks, so row counts can differ slightly between tools |
| products | product_id | 32,951 | one product | Category names are in Portuguese |
| sellers | seller_id | 3,095 | one seller | Seller location (zip prefix, city, state) |
| geolocation | (none – zip prefix, many rows) | 1,000,163 | one postcode-prefix map point | Largest table; several points per zip prefix, so it must be deduplicated before joining |
| category translation | product_category_name | 71 | one category name translation | Portuguese to English category names |

### Profiling findings

- **Customer identity:** customer_id is unique per order (99,441 distinct values), but there are only 96,096 distinct customer_unique_id values. So 3,345 orders came from repeat customers. Customer dimensions and counts must use customer_unique_id, or customers would be overcounted by 3,345.
- **Fan-out:** order_items and payments both have more rows than orders. Joining orders to either table multiplies order rows, so order-level totals must be calculated carefully to avoid double counting.
- **Size:** geolocation (over 1 million rows) is far larger than any other table, and has no unique key. It needs deduplication and care for performance.

## Fact table grain

**One row per order item (order_id + order_item_id).**

Why: price, freight value and seller are recorded per item, not per order. Choosing the order item as the grain means every sales figure can be added up correctly to any level (order, product, seller, customer, day) without double counting.

## Dimensions

| Dimension | Natural key | SCD type | Why |
| --- | --- | --- | --- |
| dim_customer | customer_unique_id | Type 2 | Customer location can change over time; history is kept so each sale is linked to where the customer lived at the time |
| dim_seller | seller_id | Type 2 | Seller location can change; history keeps regional sales reports accurate for past periods |
| dim_product | product_id | Type 1 | Product changes are treated as corrections (e.g. fixing a category), so the old value is overwritten |
| dim_date | date | Static | A fixed calendar table, generated once, that never changes |

## SCD2 approach

*To complete when building the customer snapshot (Project 1, SCD Type 2 step).*

Will cover: how change events are ordered by effective timestamp; how multiple same-day changes, late-arriving changes, deletes and reprocessing are handled.

## Personal data

See [Personal data protection (UK GDPR)](#personal-data-protection-uk-gdpr) below.

### Data-quality findings 

| Check | Rows found | Rule for silver |
| --- | --- | --- |
| Order status breakdown | 96,478 delivered; 625 canceled; 609 unavailable; 1,729 in progress | Only delivered orders count as completed sales in gold. Canceled and unavailable orders are excluded from revenue. |
| Delivered but no customer delivery date | 8 | Flag with `dq_issue = 'delivered_no_date'` and send to quarantine for review |
| Canceled but has a delivery date | 6 | Flag with `dq_issue = 'canceled_with_delivery'` and send to quarantine for review |
| Delivered before purchase | 0 | Keep as an automated test so future loads fail loudly if this ever happens |
| Item prices | Max 6,735.00; no obvious outliers | Add a test that price is greater than 0 |

### Keys and joins 


| Check | Result | What it means |
| --- | --- | --- |
| order_id uniqueness | 99,441 rows, 99,441 distinct, 0 empty | order_id is a valid primary key for orders |
| Repeat customers | 2,997 people ordered more than once | About 3% of customers returned; customer counts must use customer_unique_id |
| Orphan order items | 0 | Items whose order_id has no matching order would be silently dropped by an INNER JOIN |
| Fan-out: items joined to payments | True revenue 13,591,643.70; after join 14,209,115.34; inflated by 617,471.64 (about 4.5%) | Orders with several payment rows duplicate their items. Rule for gold: never sum item prices after joining payments; aggregate payments to one row per order first, then join |

## Bronze layer 

- Location: Unity Catalog `workspace.bronze`; raw files in volume `workspace.bronze.landing/olist/`.
- 9 Delta tables, all columns kept as strings (exactly as received; typing happens in silver).
- Audit columns on every row: `_ingested_at` (load time) and `_source_file` (lineage).
- Loads are idempotent (`overwrite`), so reruns are safe.
- Reconciliation: all 9 bronze row counts match the source files exactly (e.g. orders 99,441; geolocation 1,000,163).

## Silver layer

| Table | Changes from bronze | Quarantine / removed |
| --- | --- | --- |
| silver.orders | Status trimmed and lowercased; 5 date columns typed as timestamps (0 failed conversions) | 14 rows quarantined: delivered_no_date, canceled_with_delivery |
| silver.order_items | Prices and freight as DECIMAL(10,2); item number as INT; shipping date typed | 0 rows quarantined |
| silver.customers | City lowercased, state uppercased, postcode padded to 5 characters (kept as text) | None |
| silver.reviews | One review per order (latest by answer time) using ROW_NUMBER, to prevent fan-out | 551 duplicate reviews removed (99,224 to 98,673) |

Reconciliation: bronze = silver + quarantine for orders (99,441 = 99,427 + 14), order_items (112,650) and customers (99,441). All OK.

Note: empty delivery dates are not errors; 2,965 orders were never delivered (canceled, unavailable or in transit).

## Silver layer (part 2)

| Table | Changes from bronze | Quarantine / notes |
| --- | --- | --- |
| silver.payments | Sequential and instalments as INT; payment_value as DECIMAL(10,2); payment type cleaned | Rows with missing, negative or not_defined payments quarantined; bronze 103,886 = silver + quarantine |
| silver.products | Source typos fixed (lenght to length); measurements as INT; English category names joined from the translation table | 610 products have no category; 2 categories have no translation; 6 products flagged is_weight_suspect (flag, not quarantine, so no order items are orphaned) |
| silver.sellers | City lowercased, state uppercased, postcode padded to 5 characters | None |
| silver.geolocation | Coordinates typed; points outside Brazil quarantined; aggregated to one row per postcode prefix (average point, most common city and state) | 42 points quarantined; 1,000,121 valid points aggregated to 19,010 postcode prefixes, preventing fan-out |

## Personal data protection (UK GDPR)

- Olist is anonymised, so names, emails and phones were simulated with Faker (seeded, so the data is repeatable) for all 96,096 real customers.
- Raw personal data lives only in `workspace.restricted.customer_profiles_raw`.
- `workspace.restricted.token_vault` maps each real value to a random UUID token: 233,661 tokens (names repeat across customers; emails are unique).
- New tokens are created with a left anti join, so reruns add zero tokens (idempotent).
- `workspace.silver.customer_profiles` contains tokens only. Checks: no personal columns, 0 missing tokens, 96,096 rows = real customers.
- Access: analysts read silver and gold only; the restricted schema is limited to the data protection team.
- Right to erasure: deleting a person's vault entries makes their tokens meaningless everywhere, without rebuilding other tables.
- Simulated house moves: `workspace.bronze.customer_address_changes` (4,782 customers, 6,010 moves) for SCD Type 2.

## Gold layer (star schema)

Built with dbt (`dbt/models/marts/`) as tables in `workspace.gold`, on top of staging views in `workspace.staging`.

| Model | Grain | Purpose |
| --- | --- | --- |
| dim_date | One row per day, 2016-01-01 to 2018-12-31 | Calendar attributes (year, quarter, month, weekday, weekend flag); generated as a date spine so days with no sales still exist |
| dim_product | One row per product | Surrogate key, English category, measurements and is_weight_suspect flag |
| dim_seller | One row per seller | Surrogate key, location, and the map point of the postcode prefix (left join, so no seller is lost) |
| fact_sales | One row per order item | Main sales fact: price, freight, item_total, delivery_days, is_late, is_delivered; keys to product, seller and date |
| fct_orders | One row per order | Order-level fact: item count and value, payment total, instalments, review score, delivery_days, is_late |

- **Quarantined orders are excluded:** fact_sales inner joins items to orders, so the 15 items belonging to the 14 orders quarantined in silver are left out (112,650 - 15 = 112,635 rows). fct_orders has 99,427 rows (99,441 - 14).
- **Fan-out design:** payments are never joined to fact_sales, because orders with several payment rows would duplicate items and inflate revenue (about 4.5%, see Keys and joins). Instead, fct_orders aggregates items, payments and reviews to one row per order in separate CTEs first, then joins them.
- **Tests:** unique and not_null on every key; relationships from fact keys to all dimensions (severity error); singular test `assert_sales_match_orders` reconciles item price between fact_sales and fct_orders.
- **Results:** 14 models built; 34 tests, 33 passed and 1 warned (the expected 15 items of quarantined orders in staging). Item revenue in fact_sales is 13,589,748.34, of which 13,220,248.93 is from delivered orders.
