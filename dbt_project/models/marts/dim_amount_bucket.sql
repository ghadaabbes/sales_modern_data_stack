{{
  config(
    materialized='table',
    tags=['marts', 'dimensions']
  )
}}

-- One row per amount bucket (small / medium / large / premium).
-- min_amount indicates the lower threshold of each bucket.
SELECT
  amount_bucket,
  CASE amount_bucket
    WHEN 'small'   THEN 0
    WHEN 'medium'  THEN 50
    WHEN 'large'   THEN 200
    WHEN 'premium' THEN 500
  END AS min_amount,
  CASE amount_bucket
    WHEN 'small'   THEN 49.99
    WHEN 'medium'  THEN 199.99
    WHEN 'large'   THEN 499.99
    WHEN 'premium' THEN NULL
  END AS max_amount
FROM (
  SELECT DISTINCT amount_bucket
  FROM {{ ref('int_orders_enriched') }}
)
