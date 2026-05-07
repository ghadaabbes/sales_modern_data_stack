{{
  config(
    materialized='view',
    tags=['intermediate']
  )
}}

SELECT
  order_id,
  customer_id,
  order_date,
  amount,
  status,
  country,

  -- Derived time dimensions
  DATE_TRUNC('year',    order_date) AS order_year,
  DATE_TRUNC('month',   order_date) AS order_month,
  DATE_TRUNC('quarter', order_date) AS order_quarter,
  DAYOFWEEK(order_date)             AS day_of_week,
  WEEKOFYEAR(order_date)            AS week_of_year,

  -- Amount bucket segmentation
  CASE
    WHEN amount < 50   THEN 'small'
    WHEN amount < 200  THEN 'medium'
    WHEN amount < 500  THEN 'large'
    ELSE               'premium'
  END AS amount_bucket,

  -- Completed order flag
  CASE WHEN status = 'completed' THEN 1 ELSE 0 END AS is_completed

FROM {{ ref('stg_orders') }}
