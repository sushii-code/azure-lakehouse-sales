-- Staging model for reviews: one review per order (silver already kept only the latest).
-- That makes order_id unique here, so joining reviews to orders cannot cause fan-out.

with source as (

    select * from {{ source('silver', 'reviews') }}

)

select
    review_id,
    order_id,
    review_score,
    review_comment_title as comment_title,
    review_comment_message as comment_message,
    review_creation_date as created_at,
    review_answer_timestamp as answered_at
from source
