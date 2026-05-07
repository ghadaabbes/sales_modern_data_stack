{{
  config(
    materialized='table',
    tags=['marts', 'sales']
  )
}}

SELECT
  order_id,
  customer_id,
  order_date,
  order_year,
  order_month,
  order_quarter,
  day_of_week,
  week_of_year,
  amount,
  amount_bucket,
  status,
  is_completed,
  country
FROM {{ ref('int_orders_enriched') }}
