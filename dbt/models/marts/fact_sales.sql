-- Sales fact. Grain: one row per order item (order_id + order_item_id).
-- Price, freight and seller are recorded per item, so this grain lets every sales figure
-- add up correctly to any level (order, product, seller, customer, day).
--
-- INNER JOIN to stg_orders on purpose: 15 items belong to the 14 orders quarantined in
-- silver (delivered with no date, or canceled with a delivery date). Their order details
-- are untrustworthy, so those items are excluded: 112,650 items - 15 = 112,635 rows.
--
-- Payments are NOT joined here. An order can have several payment rows, so joining them
-- would repeat each item once per payment row (fan-out) and inflate revenue (by about 4.5%,
-- found on Day 4). Payment totals live in fct_orders, aggregated to one row per order.

with order_items as (

    select * from {{ ref('stg_order_items') }}

),

orders as (

    select * from {{ ref('stg_orders') }}

),

customers as (

    select * from {{ ref('stg_customers') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['order_items.order_id', 'order_items.order_item_id']) }} as sales_key,
    order_items.order_id,
    order_items.order_item_id,
    {{ dbt_utils.generate_surrogate_key(['order_items.product_id']) }} as product_key,
    {{ dbt_utils.generate_surrogate_key(['order_items.seller_id']) }}  as seller_key,
    customers.customer_unique_id,   -- becomes customer_key when dim_customer is built (Day 10)
    cast(date_format(orders.purchased_at, 'yyyyMMdd') as int)          as purchase_date_key,
    orders.order_status,
    order_items.price,
    order_items.freight_value,
    order_items.price + order_items.freight_value                       as item_total,
    datediff(orders.delivered_to_customer_at, orders.purchased_at)      as delivery_days,
    -- NULL for orders not yet delivered (we can't know yet if they will be late)
    orders.delivered_to_customer_at > orders.estimated_delivery_at      as is_late,
    orders.order_status = 'delivered'                                   as is_delivered
from order_items
inner join orders
    on order_items.order_id = orders.order_id
left join customers
    on orders.customer_id = customers.customer_id
