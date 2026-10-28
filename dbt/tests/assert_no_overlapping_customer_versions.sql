-- SCD Type 2 rule: a customer's versions must not overlap in time.
-- If a version started before the previous one ended, a sale in that gap would match two
-- versions in the fact_sales as-of join and be counted twice.
-- LAG looks at the previous version of the same customer. Returns (fails on) any overlap.

with ordered_versions as (

    select
        customer_unique_id,
        version_number,
        valid_from,
        lag(valid_to) over (
            partition by customer_unique_id order by valid_from
        ) as previous_valid_to
    from {{ ref('dim_customer') }}

)

select *
from ordered_versions
where valid_from < previous_valid_to
