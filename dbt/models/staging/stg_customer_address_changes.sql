-- Staging model for customer address changes: one row per simulated house move.
-- Reads from bronze (there is no silver table for it), so the city/state cleaning that
-- silver does for other tables happens here, using the same rules as stg_customers.

with source as (

    select * from {{ source('bronze', 'customer_address_changes') }}

)

select
    customer_unique_id,
    lower(trim(new_city))  as city,
    upper(trim(new_state)) as state,
    effective_at
from source
