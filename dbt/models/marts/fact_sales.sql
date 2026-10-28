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
--
-- customer_key comes from an "as-of join" to dim_customer (SCD Type 2): for each sale, pick
-- the customer version whose validity window contains the purchase time
-- (valid_from <= purchased_at < valid_to, or no valid_to for the current version).
-- Versions never overlap, so exactly one version matches and the row count does not change.
--
-- Incremental (Day 12): instead of rebuilding all 112,635 rows every run, dbt only processes
-- sales purchased since the newest sale already in the table (minus a 3-day safety window)
-- and MERGEs them in on sales_key: existing rows are updated, new rows are inserted.
-- Limitation: changes to older sales (e.g. a late status update, or a late-arriving customer
-- move that changes which dim_customer version applies) are only picked up by a full refresh.

{# materialized='incremental': keep the existing table and only add/update rows            #}
{# incremental_strategy='merge': MERGE INTO - update rows that match, insert the rest         #}
{# unique_key='sales_key': how MERGE decides a row "matches" (one row per order item)         #}
{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='sales_key'
    )
}}

with order_items as (

    select * from {{ ref('stg_order_items') }}

),

orders as (

    select * from {{ ref('stg_orders') }}

),

customers as (

    select * from {{ ref('stg_customers') }}

),

dim_customer as (

    select * from {{ ref('dim_customer') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['order_items.order_id', 'order_items.order_item_id']) }} as sales_key,
    order_items.order_id,
    order_items.order_item_id,
    {{ dbt_utils.generate_surrogate_key(['order_items.product_id']) }} as product_key,
    {{ dbt_utils.generate_surrogate_key(['order_items.seller_id']) }}  as seller_key,
    dim_customer.customer_key,      -- the customer's address version at purchase time
    customers.customer_unique_id,
    cast(date_format(orders.purchased_at, 'yyyyMMdd') as int)          as purchase_date_key,
    orders.purchased_at,            -- exact purchase time; the incremental filter below needs it
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
left join dim_customer
    on customers.customer_unique_id = dim_customer.customer_unique_id
    and orders.purchased_at >= dim_customer.valid_from
    and (dim_customer.valid_to is null or orders.purchased_at < dim_customer.valid_to)

{% if is_incremental() %}               -- true only on a normal run when the table already exists (skipped on --full-refresh)
where orders.purchased_at >= (          -- only sales purchased on or after...
    select max(purchased_at) - interval 3 days   -- ...the newest sale already loaded, minus 3 days (lookback window)
    from {{ this }}                     -- {{ this }} = the existing workspace.gold.fact_sales table
)
{% endif %}                             -- end of the incremental-only filter
