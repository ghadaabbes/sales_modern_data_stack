{{
  config(
    materialized='incremental',
    unique_key='order_id',
    on_schema_change='sync_all_columns',
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

{% if is_incremental() %}
-- 3-day lookback to handle late-arriving or updated orders.
-- On first run (full refresh), all rows are loaded.
WHERE order_date >= (
  SELECT DATEADD('day', -3, MAX(order_date)) FROM {{ this }}
)
{% endif %}
