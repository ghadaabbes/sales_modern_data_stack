{{
  config(
    materialized='incremental',
    unique_key='customer_id',
    on_schema_change='sync_all_columns',
    tags=['marts', 'customers']
  )
}}

-- On incremental runs: recompute only customers who had recent order activity.
-- Lifetime metrics (LTV, total_orders, etc.) are always computed from their
-- full order history, not just the incremental window.

{% if is_incremental() %}

WITH updated_customers AS (
  -- Customers with orders in the last 3 days
  SELECT DISTINCT customer_id
  FROM {{ ref('fact_sales') }}
  WHERE order_date >= (
    SELECT DATEADD('day', -3, MAX(last_order_date)) FROM {{ this }}
  )
),

{% else %}

WITH updated_customers AS (
  -- Full refresh: include all customers
  SELECT DISTINCT customer_id FROM {{ ref('fact_sales') }}
),

{% endif %}

customer_orders AS (
  SELECT
    f.customer_id,
    COUNT(DISTINCT f.order_id)                            AS total_orders,
    SUM(f.amount)                                         AS lifetime_value,
    AVG(f.amount)                                         AS avg_order_value,
    MIN(f.order_date)                                     AS first_order_date,
    MAX(f.order_date)                                     AS last_order_date,
    DATEDIFF('day', MIN(f.order_date), MAX(f.order_date)) AS customer_lifespan_days,
    COUNT(DISTINCT f.country)                             AS countries_count,
    SUM(f.is_completed)                                   AS completed_orders,
    COUNT(DISTINCT f.order_id) - SUM(f.is_completed)      AS non_completed_orders
  FROM {{ ref('fact_sales') }} f
  -- Always recompute full history for the matched customers
  WHERE f.customer_id IN (SELECT customer_id FROM updated_customers)
  GROUP BY f.customer_id
),

rfm AS (
  SELECT
    customer_id,
    total_orders,
    lifetime_value,
    avg_order_value,
    first_order_date,
    last_order_date,
    customer_lifespan_days,
    countries_count,
    completed_orders,
    non_completed_orders,

    -- Recency: days since last order
    DATEDIFF('day', last_order_date, CURRENT_DATE) AS days_since_last_order,

    -- Simplified RFM customer segmentation
    CASE
      WHEN total_orders = 1                                    THEN 'one-time'
      WHEN total_orders <= 3 AND lifetime_value < 500          THEN 'occasional'
      WHEN total_orders > 3  AND lifetime_value >= 500         THEN 'loyal'
      WHEN lifetime_value >= 2000                              THEN 'vip'
      ELSE                                                          'regular'
    END AS customer_segment,

    -- Order completion rate
    ROUND(completed_orders / NULLIF(total_orders, 0) * 100, 2) AS completion_rate_pct

  FROM customer_orders
)

SELECT * FROM rfm
