-- Staging model for products: one row per product.
-- Drops the "product_" prefix from measurement columns and keeps both Portuguese and English category names.

with source as (

    select * from {{ source('silver', 'products') }}

)

select
    product_id,
    product_category_name      as category_name_portuguese,
    category_english           as category_name_english,
    product_name_length        as name_length,
    product_description_length as description_length,
    product_photos_qty         as photos_qty,
    product_weight_g           as weight_g,
    product_length_cm          as length_cm,
    product_height_cm          as height_cm,
    product_width_cm           as width_cm,
    is_weight_suspect
from source
