-- Product dimension. Grain: one row per product.
-- product_key is a surrogate key (a hash of product_id), so the star schema joins on
-- one consistent key type that does not depend on the source system's ids.
-- SCD Type 1: product changes are corrections, so this table is simply rebuilt.

with products as (

    select * from {{ ref('stg_products') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['product_id']) }} as product_key,
    product_id,
    category_name_english as category_english,
    name_length,
    description_length,
    photos_qty,
    weight_g,
    length_cm,
    height_cm,
    width_cm,
    is_weight_suspect
from products
