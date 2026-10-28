-- Staging model for customer profiles: one row per real customer, tokens only.
-- No names, emails or phones ever reach dbt; the real values stay in workspace.restricted.

with source as (

    select * from {{ source('silver', 'customer_profiles') }}

)

select
    customer_unique_id,
    full_name_token,
    email_token,
    phone_token
from source
