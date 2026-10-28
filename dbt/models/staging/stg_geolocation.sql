-- Staging model for geolocation: one row per postcode prefix (silver averaged about 1 million points).
-- Joins to customers and sellers on zip_code_prefix without duplicating rows.

with source as (

    select * from {{ source('silver', 'geolocation') }}

)

select
    zip_code_prefix,
    lat as latitude,
    lng as longitude,
    city,
    state,
    points_averaged
from source
