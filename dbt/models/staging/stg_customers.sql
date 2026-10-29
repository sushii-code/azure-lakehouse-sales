-- Staging model for customers: one row per customer_id (a new id on every order).
-- customer_unique_id identifies the real person and is what customer counts must use.

with source as (

    select * from {{ source('silver', 'customers') }}

)

select
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix as zip_code_prefix,
    customer_city as city,
    customer_state as state
from source
