-- Queries behind the "Olist Sales Overview" dashboard in Databricks AI/BI:
-- 4 counters, a line chart, 2 bar charts and a pie chart.
-- Read-only: SELECT statements only. Run one query at a time. Revenue = sum of item price, excluding freight.
-- Every query covers delivered orders only, because only those count as completed sales.


-- =====================================================================
-- Query 1: KPI totals
-- Shows: total revenue, orders, customers and average order value.
-- Chart: 4 counter (single number) tiles, one per column.
-- =====================================================================
select
    round(sum(price), 2) as total_revenue,                                  -- money from all delivered items
    count(distinct order_id) as total_orders,                               -- an order with 3 items counts once
    count(distinct customer_unique_id) as total_customers,                  -- real people, not per-order customer ids
    round(sum(price) / count(distinct order_id), 2) as average_order_value  -- revenue per order
from workspace.gold.fact_sales                                              -- one row per order item
where is_delivered;                                                         -- completed sales only


-- =====================================================================
-- Query 2: Monthly revenue trend
-- Shows: revenue for each month, oldest first.
-- Chart: line chart (x = revenue_month, y = revenue).
-- =====================================================================
select
    date_trunc('month', dates.date_day) as revenue_month,   -- first day of the month, for the x-axis
    round(sum(sales.price), 2) as revenue                   -- that month's revenue
from workspace.gold.fact_sales as sales                     -- one row per order item
inner join workspace.gold.dim_date as dates                 -- calendar table
    on sales.purchase_date_key = dates.date_key             -- match each sale to its purchase day
where sales.is_delivered                                    -- completed sales only
    and dates.date_day between '2017-01-01' and '2018-08-31' -- leave out the sparse months at both ends of the data
group by date_trunc('month', dates.date_day)                -- one row per month
order by revenue_month;                                     -- oldest month first


-- =====================================================================
-- Query 3: Top 10 product categories by revenue
-- Shows: the 10 categories that earn the most, with English names.
-- Chart: bar chart (x = category, y = revenue).
-- =====================================================================
select
    products.category_english as category,          -- English category name
    round(sum(sales.price), 2) as revenue           -- that category's revenue
from workspace.gold.fact_sales as sales             -- one row per order item
inner join workspace.gold.dim_product as products   -- product details
    on sales.product_key = products.product_key     -- match each sale to its product
where sales.is_delivered                            -- completed sales only
group by products.category_english                  -- one row per category
order by revenue desc                               -- biggest first
limit 10;                                           -- keep the top 10


-- =====================================================================
-- Query 4: Revenue and orders by customer state
-- Shows: where sales come from. customer_key points to the address version valid at
-- purchase time (SCD Type 2), so a customer who later moved still counts in the old state.
-- Chart: bar chart (x = state, y = revenue; add orders as a second series if you like).
-- =====================================================================
select
    customers.state,                                -- customer's state when they bought
    round(sum(sales.price), 2) as revenue,          -- that state's revenue
    count(distinct sales.order_id) as orders        -- that state's number of orders
from workspace.gold.fact_sales as sales             -- one row per order item
inner join workspace.gold.dim_customer as customers -- customer address versions
    on sales.customer_key = customers.customer_key  -- match each sale to the version at purchase time
where sales.is_delivered                            -- completed sales only
group by customers.state                            -- one row per state
order by revenue desc;                              -- biggest first


-- =====================================================================
-- Query 5: Delivery performance
-- Shows: the share of delivered orders that arrived on time vs late.
-- Late = delivered after the estimated delivery date.
-- Chart: pie chart or bar chart (category = delivery_status, value = pct_of_orders).
-- =====================================================================
select
    case when is_late then 'Late' else 'On time' end as delivery_status,    -- readable label
    count(*) as orders,                                                     -- orders in this group
    round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_orders     -- group's share of all delivered orders
from workspace.gold.fct_orders                                              -- one row per order
where order_status = 'delivered'                                            -- delivered orders only
    and is_late is not null                                                 -- only orders where lateness is known
group by case when is_late then 'Late' else 'On time' end                   -- one row per label
order by orders desc;                                                       -- biggest group first
