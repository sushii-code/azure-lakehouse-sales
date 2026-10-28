-- Staging model for payments: one row per payment method used for an order.
-- An order can have several rows, so payments must be summed per order before joining to items.

with source as (

    select * from {{ source('silver', 'payments') }}

)

select
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
from source
