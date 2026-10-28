-- Reconciliation report. Grain: one row per source table.
-- Follows every table from bronze through silver (and quarantine) to gold, and checks that
-- each row is either kept, quarantined, or removed on purpose for a documented reason.
-- If rows are lost or duplicated anywhere in the pipeline, check_passed becomes false and
-- the test assert_reconciliation_all_passed fails the build.
--
-- All counts are computed once in the counts CTE (each a COUNT(*) subquery), then each
-- table gets one row via UNION ALL.

with counts as (

    select
        -- orders
        (select count(*) from {{ source('bronze', 'orders') }})                 as bronze_orders,
        (select count(*) from {{ source('silver', 'orders') }})                 as silver_orders,
        (select count(*) from {{ source('silver', 'orders_quarantine') }})      as quarantine_orders,
        (select count(*) from {{ ref('fct_orders') }})                          as gold_orders,

        -- order items
        (select count(*) from {{ source('bronze', 'order_items') }})            as bronze_items,
        (select count(*) from {{ source('silver', 'order_items') }})            as silver_items,
        (select count(*) from {{ source('silver', 'order_items_quarantine') }}) as quarantine_items,
        (select count(*)
         from {{ source('silver', 'order_items') }}
         where order_id in (select order_id from {{ source('silver', 'orders_quarantine') }})
        )                                                                       as items_of_quarantined_orders,
        (select count(*) from {{ ref('fact_sales') }})                          as gold_items,

        -- payments
        (select count(*) from {{ source('bronze', 'payments') }})               as bronze_payments,
        (select count(*) from {{ source('silver', 'payments') }})               as silver_payments,
        (select count(*) from {{ source('silver', 'payments_quarantine') }})    as quarantine_payments,

        -- customers
        (select count(*) from {{ source('bronze', 'customers') }})              as bronze_customers,
        (select count(*) from {{ source('silver', 'customers') }})              as silver_customers,
        (select count(distinct customer_unique_id)
         from {{ source('silver', 'customers') }})                              as silver_unique_customers,
        -- people whose every order was quarantined (no valid first order, so no dim_customer row)
        (select count(*) from (
            select customers.customer_unique_id
            from {{ source('silver', 'customers') }} as customers
            left join {{ source('silver', 'orders') }} as orders
                on customers.customer_id = orders.customer_id
            left join {{ source('silver', 'orders_quarantine') }} as quarantined
                on customers.customer_id = quarantined.customer_id
            group by customers.customer_unique_id
            having count(orders.order_id) = 0 and count(quarantined.order_id) > 0
        ))                                                                      as customers_only_quarantined,
        (select count(*) from {{ ref('dim_customer') }} where is_current)       as gold_current_customers,

        -- reviews
        (select count(*) from {{ source('bronze', 'reviews') }})                as bronze_reviews,
        (select count(distinct order_id) from {{ source('bronze', 'reviews') }}) as bronze_reviewed_orders,
        (select count(*) from {{ source('silver', 'reviews') }})                as silver_reviews,

        -- products and sellers
        (select count(*) from {{ source('bronze', 'products') }})               as bronze_products,
        (select count(*) from {{ source('silver', 'products') }})               as silver_products,
        (select count(*) from {{ ref('dim_product') }})                         as gold_products,
        (select count(*) from {{ source('bronze', 'sellers') }})                as bronze_sellers,
        (select count(*) from {{ source('silver', 'sellers') }})                as silver_sellers,
        (select count(*) from {{ ref('dim_seller') }})                          as gold_sellers,

        -- geolocation: valid points are counted independently with the same Brazil box rule as
        -- silver (not as bronze - quarantine), so bronze = valid + quarantine is a real check
        (select count(*) from {{ source('bronze', 'geolocation') }})            as bronze_geo,
        (select count(*) from {{ source('bronze', 'geolocation') }}
         where try_cast(geolocation_lat as double) between -34 and 6
           and try_cast(geolocation_lng as double) between -74 and -34)         as bronze_geo_valid_points,
        (select count(distinct lpad(trim(geolocation_zip_code_prefix), 5, '0'))
         from {{ source('bronze', 'geolocation') }}
         where try_cast(geolocation_lat as double) between -34 and 6
           and try_cast(geolocation_lng as double) between -74 and -34)         as bronze_geo_valid_prefixes,
        (select count(*) from {{ source('silver', 'geolocation_quarantine') }}) as quarantine_geo,
        (select count(*) from {{ source('silver', 'geolocation') }})            as silver_geo_prefixes

)

select
    'orders'                                as table_name,
    bronze_orders                           as bronze_rows,
    silver_orders                           as silver_rows,
    quarantine_orders                       as quarantine_rows,
    cast(0 as bigint)                       as removed_on_purpose,
    gold_orders                             as gold_rows,
    'gold.fct_orders'                       as gold_table,
    bronze_orders = silver_orders + quarantine_orders
        and silver_orders = gold_orders     as check_passed,
    'Every bronze order is in silver or quarantine, and every silver order is in fct_orders.' as explanation
from counts

union all

select
    'order_items',
    bronze_items,
    silver_items,
    quarantine_items,
    items_of_quarantined_orders,
    gold_items,
    'gold.fact_sales',
    bronze_items = silver_items + quarantine_items
        and gold_items = silver_items - items_of_quarantined_orders,
    'fact_sales has every silver item except those belonging to quarantined orders, which are excluded on purpose.'
from counts

union all

select
    'payments',
    bronze_payments,
    silver_payments,
    quarantine_payments,
    cast(0 as bigint),
    cast(null as bigint),
    'gold.fct_orders (aggregated per order)',
    bronze_payments = silver_payments + quarantine_payments,
    'Every bronze payment is in silver or quarantine; gold only stores payment totals per order, so rows are not compared.'
from counts

union all

select
    'customers',
    bronze_customers,
    silver_customers,
    cast(0 as bigint),
    customers_only_quarantined,
    gold_current_customers,
    'gold.dim_customer (current rows)',
    bronze_customers = silver_customers
        and gold_current_customers = silver_unique_customers - customers_only_quarantined,
    'dim_customer has one current row per real person, except people whose only orders were quarantined (no starting address).'
from counts

union all

select
    'reviews',
    bronze_reviews,
    silver_reviews,
    cast(0 as bigint),
    bronze_reviews - silver_reviews,
    cast(null as bigint),
    'gold.fct_orders (review_score per order)',
    silver_reviews = bronze_reviewed_orders,
    'Silver keeps exactly one review per reviewed order; the removed rows are duplicate reviews for the same order.'
from counts

union all

select
    'products',
    bronze_products,
    silver_products,
    cast(0 as bigint),
    cast(0 as bigint),
    gold_products,
    'gold.dim_product',
    bronze_products = silver_products and silver_products = gold_products,
    'Every product reaches dim_product; suspect weights are flagged, not removed, so no sale loses its product.'
from counts

union all

select
    'sellers',
    bronze_sellers,
    silver_sellers,
    cast(0 as bigint),
    cast(0 as bigint),
    gold_sellers,
    'gold.dim_seller',
    bronze_sellers = silver_sellers and silver_sellers = gold_sellers,
    'Every seller reaches dim_seller unchanged in number; only text and postcode formats are cleaned.'
from counts

union all

select
    'geolocation',
    bronze_geo,
    bronze_geo_valid_points,
    quarantine_geo,
    cast(0 as bigint),
    silver_geo_prefixes,
    'silver.geolocation (one row per postcode prefix)',
    bronze_geo = bronze_geo_valid_points + quarantine_geo
        and silver_geo_prefixes = bronze_geo_valid_prefixes,
    'Every map point is valid or quarantined, and valid points are aggregated to one row per postcode prefix to prevent fan-out.'
from counts
