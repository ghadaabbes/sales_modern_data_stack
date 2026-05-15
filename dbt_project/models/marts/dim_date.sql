{{
  config(
    materialized='table',
    tags=['marts', 'dimensions']
  )
}}

-- One row per distinct order date.
-- Carries all derived time attributes so downstream models
-- never need to recompute DATE_TRUNC or DAYOFWEEK.
SELECT DISTINCT
  order_date,
  order_year,
  order_month,
  order_quarter,
  day_of_week,
  week_of_year
FROM {{ ref('int_orders_enriched') }}
