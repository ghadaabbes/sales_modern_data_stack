{{
  config(
    materialized='table',
    tags=['marts', 'kpi']
  )
}}

SELECT
  order_date,
  country,
  COUNT(DISTINCT order_id)  AS total_orders,
  SUM(amount)               AS revenue,
  AVG(amount)               AS avg_order_value
FROM {{ ref('fact_sales') }}
GROUP BY order_date, country
