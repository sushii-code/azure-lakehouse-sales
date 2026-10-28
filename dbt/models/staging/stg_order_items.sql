-- Staging model for order items: one row per item within an order.
-- This is the grain of the future fact table; price and freight are DECIMAL(10,2) from silver.

with source as (

    select * from {{ source('silver', 'order_items') }}

)

select
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date as shipping_limit_at,
    price,
    freight_value
from source
