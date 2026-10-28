-- Known gap 2: the 14 customers missing from dim_customer.
-- Proves that the people missing from dim_customer are EXACTLY the people whose only order
-- was quarantined in silver (no valid first order, so no starting address) - nobody else.
-- It compares two lists person by person, so it checks which customers, not just how many.
-- dbt fails the test if it returns any rows.

-- List A: real people in silver who have no row in dim_customer
with missing_customers as (

    select distinct customer_unique_id                      -- every real person in silver
    from {{ source('silver', 'customers') }}
    except                                                  -- minus...
    select distinct customer_unique_id                      -- ...every person in dim_customer
    from {{ ref('dim_customer') }}

),

-- List B: people whose orders are ALL in quarantine (expected: 14)
only_quarantined_customers as (

    select customers.customer_unique_id                     -- one row per real person
    from {{ source('silver', 'customers') }} as customers   -- one customers row per order
    left join {{ source('silver', 'orders') }} as orders    -- their valid orders (if any)
        on customers.customer_id = orders.customer_id
    left join {{ source('silver', 'orders_quarantine') }} as quarantined   -- their quarantined orders (if any)
        on customers.customer_id = quarantined.customer_id
    group by customers.customer_unique_id                   -- count per person...
    having count(orders.order_id) = 0                       -- ...no valid order at all
       and count(quarantined.order_id) > 0                  -- ...and at least one quarantined order

)

-- People missing from dim_customer for some other reason (a customer lost by mistake)
select 'missing_but_has_valid_order' as problem, mismatch.*
from (
    select * from missing_customers                         -- in list A
    except
    select * from only_quarantined_customers                -- but not in list B
) as mismatch

union all

-- People with only quarantined orders who still got a dim_customer row (should not happen)
select 'only_quarantined_but_in_dim_customer' as problem, mismatch.*
from (
    select * from only_quarantined_customers                -- in list B
    except
    select * from missing_customers                         -- but not in list A
) as mismatch
