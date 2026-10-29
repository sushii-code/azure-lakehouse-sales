-- Staging model for sellers: one row per seller.
-- Location columns use the same short names as stg_customers (zip_code_prefix, city, state).

with source as (

    select * from {{ source('silver', 'sellers') }}

)

select
    seller_id,
    seller_zip_code_prefix as zip_code_prefix,
    seller_city as city,
    seller_state as state
from source
