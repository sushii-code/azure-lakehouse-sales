-- Known gap 1: the 15 order items left out of fact_sales.
-- Proves that the items missing from fact_sales are EXACTLY the items whose order was
-- quarantined in silver - no more (a sale lost by mistake) and no fewer (a broken order leaking in).
-- It compares two lists item by item, so it checks which items, not just how many.
-- dbt fails the test if it returns any rows.

-- List A: items that exist in silver but did not reach fact_sales
with excluded_items as (

    select order_id, order_item_id                          -- every silver item (the full list)
    from {{ source('silver', 'order_items') }}
    except                                                  -- minus...
    select order_id, order_item_id                          -- ...every item that is in gold
    from {{ ref('fact_sales') }}

),

-- List B: items whose order was set aside in silver quarantine (expected: 15)
items_of_quarantined_orders as (

    select order_id, order_item_id                          -- silver items...
    from {{ source('silver', 'order_items') }}
    where order_id in (                                     -- ...whose order_id appears in...
        select order_id
        from {{ source('silver', 'orders_quarantine') }}    -- ...the quarantined orders
    )

)

-- Items excluded from gold although their order was NOT quarantined (a sale lost by mistake)
select 'excluded_but_order_not_quarantined' as problem, mismatch.*
from (
    select * from excluded_items                            -- in list A
    except
    select * from items_of_quarantined_orders               -- but not in list B
) as mismatch

union all

-- Items of quarantined orders that still reached gold (a broken order leaking in)
select 'order_quarantined_but_item_in_gold' as problem, mismatch.*
from (
    select * from items_of_quarantined_orders               -- in list B
    except
    select * from excluded_items                            -- but not in list A
) as mismatch
