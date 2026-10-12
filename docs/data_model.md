# Data model

## Source tables (Olist)
| Table | Key(s) | Rows | Notes |
| --- | --- | --- | --- |
| orders | order_id | | |
| order_items | order_id + order_item_id | | |
| customers | customer_id | | customer_id is new on every order; customer_unique_id is the real person |
| payments | order_id + payment_sequential | | |
| reviews | review_id | | |
| products | product_id | | |
| sellers | seller_id | | |
| geolocation | (none – zip prefix, many rows) | | |
| category translation | product_category_name | | |

## Fact table grain
[e.g. One row per order item (order_id + order_item_id). Why: price, freight and seller are recorded per item.]

## Dimensions
| Dimension | Natural key | SCD type | Why |
| --- | --- | --- | --- |
| dim_customer | customer_unique_id | Type 2 | |
| dim_seller | seller_id | Type 2 | |
| dim_product | product_id | Type 1 | |
| dim_date | date | Static | |

## SCD2 approach
[How change events are ordered by effective timestamp; how multiple same-day changes, late arrivals, deletes and reprocessing are handled.]

## Personal data
[Which columns are dropped, which are tokenised, where the token mapping lives and who can read it.]
