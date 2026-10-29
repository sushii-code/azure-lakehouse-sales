-- Date dimension. Grain: one row per calendar day from 2016-01-01 to 2018-12-31.
-- Generated from a date spine (sequence + explode), not from the orders, so days with
-- no sales still exist and reports can show zero-sales days.
-- date_key is an INT like 20170315, which is what the facts store as purchase_date_key.

with spine as (

    select explode(sequence(to_date('2016-01-01'), to_date('2018-12-31'), interval 1 day)) as date_day

)

select
    cast(date_format(date_day, 'yyyyMMdd') as int) as date_key,
    date_day,
    year(date_day) as year,
    quarter(date_day) as quarter,
    month(date_day) as month,
    date_format(date_day, 'MMMM') as month_name,
    dayofmonth(date_day) as day_of_month,
    date_format(date_day, 'EEEE') as day_of_week_name,
    dayofweek(date_day) in (1, 7) as is_weekend   -- 1 = Sunday, 7 = Saturday
from spine
