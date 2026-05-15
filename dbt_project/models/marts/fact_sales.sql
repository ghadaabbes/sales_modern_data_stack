{{
  config(
    materialized='incremental',
    unique_key='order_id',
    on_schema_change='sync_all_columns',
    tags=['marts', 'sales']
  )
}}

-- Star schema fact table — grain: 1 row = 1 order.
-- Contains only foreign keys and the amount metric.
-- All descriptive attributes live in dimension tables.
SELECT
  order_id,
  customer_id,   -- FK → dim_customer
  order_date,    -- FK → dim_date
  status,        -- FK → dim_status
  amount_bucket, -- FK → dim_amount_bucket
  amount
FROM {{ ref('int_orders_enriched') }}

{% if is_incremental() %}
WHERE order_date >= (
  SELECT DATEADD('day', -3, MAX(order_date)) FROM {{ this }}
)
{% endif %}
