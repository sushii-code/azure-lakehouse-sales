-- Reconciliation test between the two facts.
-- fact_sales (one row per item) and fct_orders (one row per order) are built separately,
-- so for the orders that appear in both, total item price must be identical.
-- A difference would mean one of them dropped or duplicated items (e.g. fan-out).
-- dbt fails a singular test if it returns any rows; this returns a row only on a mismatch.

with sales_per_order as (

    select order_id, sum(price) as price_total
    from {{ ref('fact_sales') }}
    group by order_id

)

select
    sum(sales_per_order.price_total) as fact_sales_price_total,
    sum(fct_orders.items_value)      as fct_orders_items_value
from sales_per_order
inner join {{ ref('fct_orders') }} as fct_orders
    on sales_per_order.order_id = fct_orders.order_id
having sum(sales_per_order.price_total) <> sum(fct_orders.items_value)
