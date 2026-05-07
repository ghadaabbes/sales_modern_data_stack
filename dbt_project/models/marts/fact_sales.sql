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
  amount,
  status,
  country
FROM {{ ref('stg_orders') }}
