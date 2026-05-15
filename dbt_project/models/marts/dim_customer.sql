{{
  config(
    materialized='table',
    tags=['marts', 'dimensions']
  )
}}

-- One row per customer.
-- Country is stored here — not on the fact table.
SELECT DISTINCT
  customer_id,
  country
FROM {{ ref('stg_orders') }}
