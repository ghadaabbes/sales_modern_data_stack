{{
  config(
    materialized='table',
    tags=['marts', 'dimensions']
  )
}}

-- One row per order status.
-- is_completed flag centralised here — single source of truth.
SELECT DISTINCT
  status,
  CASE WHEN status = 'completed' THEN 1 ELSE 0 END AS is_completed
FROM {{ ref('stg_orders') }}
