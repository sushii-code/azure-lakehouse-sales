-- Seller dimension. Grain: one row per seller.
-- Adds the map point for the seller's postcode prefix. stg_geolocation has exactly one row
-- per prefix, so the join cannot duplicate sellers; it is a LEFT JOIN so sellers whose
-- prefix has no map point are kept (with empty coordinates) instead of being dropped.

with sellers as (

    select * from {{ ref('stg_sellers') }}

),

geolocation as (

    select * from {{ ref('stg_geolocation') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['sellers.seller_id']) }} as seller_key,
    sellers.seller_id,
    sellers.city,
    sellers.state,
    sellers.zip_code_prefix,
    geolocation.latitude,
    geolocation.longitude
from sellers
left join geolocation
    on sellers.zip_code_prefix = geolocation.zip_code_prefix
