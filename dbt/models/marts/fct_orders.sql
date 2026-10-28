-- Orders fact. Grain: one row per order (from stg_orders, so quarantined orders are excluded).
--
-- How fan-out is prevented: items, payments and reviews can each have several rows per order.
-- Joining them all to orders directly would multiply rows (2 items x 2 payments = 4 rows),
-- and every SUM would be wrong. So each table is first AGGREGATED to exactly one row per
-- order in its own CTE, and only then joined. One row joined to one row can never multiply.
-- LEFT JOINs keep orders that have no items, payments or review (e.g. unavailable orders).

with orders as (

    select * from {{ ref('stg_orders') }}

),

customers as (

    select * from {{ ref('stg_customers') }}

),

items_per_order as (

    select
        order_id,
        count(*)           as items_count,
        sum(price)         as items_value,
        sum(freight_value) as freight_value
    from {{ ref('stg_order_items') }}
    group by order_id

),

payments_per_order as (

    select
        order_id,
        sum(payment_value)        as payment_total,
        max(payment_installments) as max_installments,
        count(*)                  as payment_rows
    from {{ ref('stg_payments') }}
    group by order_id

),

reviews as (

    -- already one review per order (deduplicated in silver)
    select order_id, review_score from {{ ref('stg_reviews') }}

)

select
    orders.order_id,
    customers.customer_unique_id,
    cast(date_format(orders.purchased_at, 'yyyyMMdd') as int)      as purchase_date_key,
    orders.order_status,
    coalesce(items_per_order.items_count, 0)                        as items_count,
    coalesce(items_per_order.items_value, 0)                        as items_value,
    coalesce(items_per_order.freight_value, 0)                      as freight_value,
    coalesce(payments_per_order.payment_total, 0)                   as payment_total,
    payments_per_order.max_installments,
    coalesce(payments_per_order.payment_rows, 0)                    as payment_rows,
    reviews.review_score,
    datediff(orders.delivered_to_customer_at, orders.purchased_at)  as delivery_days,
    orders.delivered_to_customer_at > orders.estimated_delivery_at  as is_late
from orders
left join customers          on orders.customer_id = customers.customer_id
left join items_per_order    on orders.order_id = items_per_order.order_id
left join payments_per_order on orders.order_id = payments_per_order.order_id
left join reviews            on orders.order_id = reviews.order_id
