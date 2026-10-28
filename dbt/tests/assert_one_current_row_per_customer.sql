-- SCD Type 2 rule: every customer has exactly ONE current version.
-- Zero would mean their latest address is lost; two would double their rows in
-- "current customers" reports. Returns (fails on) any customer with a count other than 1.

select
    customer_unique_id,
    sum(case when is_current then 1 else 0 end) as current_rows
from {{ ref('dim_customer') }}
group by customer_unique_id
having sum(case when is_current then 1 else 0 end) <> 1
