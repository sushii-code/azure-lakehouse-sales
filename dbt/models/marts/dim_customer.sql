-- Customer dimension, SCD Type 2. Grain: one row per customer per address version.
--
-- SCD Type 2 keeps history: when a customer moves, the old row is closed (valid_to is set)
-- and a new row is added, instead of overwriting the address. Each sale can then be linked
-- to where the customer lived AT THE TIME of that sale, so regional reports for the past
-- stay correct after people move.
--
-- Event-based: versions are built from dated events (first order + simulated moves),
-- not from dbt snapshots comparing table copies over time. That rebuilds the full history
-- on every run, and dates come from when a change happened, not when it was loaded.
--
-- Names, emails and phones are Type 1 attributes (tokens only, the same on every version).

with customers as (

    select * from {{ ref('stg_customers') }}

),

orders as (

    select * from {{ ref('stg_orders') }}

),

-- Version 1 for each person: the address on their FIRST order.
-- customer_id is new on every order, so a person has one customers row per order;
-- ROW_NUMBER picks the row belonging to their earliest purchase.
first_address as (

    select
        customer_unique_id,
        city,
        state,
        zip_code_prefix,
        effective_at,
        1 as source_priority
    from (
        select
            customers.customer_unique_id,
            customers.city,
            customers.state,
            customers.zip_code_prefix,
            orders.purchased_at as effective_at,
            row_number() over (
                partition by customers.customer_unique_id
                order by orders.purchased_at, orders.order_id
            ) as order_rank
        from customers
        inner join orders
            on customers.customer_id = orders.customer_id
    ) as ranked_orders
    where order_rank = 1

),

-- Later versions: each simulated house move. The simulator gives no postcode.
changes as (

    select
        customer_unique_id,
        city,
        state,
        cast(null as string) as zip_code_prefix,
        effective_at,
        2 as source_priority
    from {{ ref('stg_customer_address_changes') }}

),

all_versions as (

    select * from first_address
    union all
    select * from changes

),

-- Same-time changes: if two versions start at exactly the same moment, keeping both would
-- create a version that is valid for zero seconds and two "current" candidates.
-- Keep one per (customer, effective_at): a move event wins over the first-order address,
-- because it is the newer information.
deduped as (

    select *
    from (
        select
            *,
            row_number() over (
                partition by customer_unique_id, effective_at
                order by source_priority desc, city asc, state asc
            ) as same_time_rank
        from all_versions
    ) as ranked_versions
    where same_time_rank = 1

),

-- Ordering by effective_at (when the move happened), never by load time, means a
-- late-arriving event that is loaded today but happened last year still slots into the
-- right place in the history, and the versions around it get their dates adjusted.
versioned as (

    select
        customer_unique_id,
        city,
        state,
        zip_code_prefix,
        effective_at as valid_from,
        lead(effective_at) over (
            partition by customer_unique_id order by effective_at
        ) as valid_to,
        row_number() over (
            partition by customer_unique_id order by effective_at
        ) as version_number
    from deduped

),

profiles as (

    select * from {{ ref('stg_customer_profiles') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['versioned.customer_unique_id', 'versioned.valid_from']) }} as customer_key,
    versioned.customer_unique_id,
    versioned.city,
    versioned.state,
    versioned.zip_code_prefix,
    versioned.valid_from,
    versioned.valid_to,
    versioned.valid_to is null as is_current,
    versioned.version_number,
    profiles.full_name_token,
    profiles.email_token,
    profiles.phone_token
from versioned
left join profiles
    on versioned.customer_unique_id = profiles.customer_unique_id
