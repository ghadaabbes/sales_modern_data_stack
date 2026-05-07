{{
  config(
    materialized='table',
    tags=['marts', 'customers']
  )
}}

WITH customer_orders AS (
  SELECT
    customer_id,
    COUNT(DISTINCT order_id)                            AS total_orders,
    SUM(amount)                                         AS lifetime_value,
    AVG(amount)                                         AS avg_order_value,
    MIN(order_date)                                     AS first_order_date,
    MAX(order_date)                                     AS last_order_date,
    DATEDIFF('day', MIN(order_date), MAX(order_date))   AS customer_lifespan_days,
    COUNT(DISTINCT country)                             AS countries_count,
    SUM(is_completed)                                   AS completed_orders,
    COUNT(DISTINCT order_id) - SUM(is_completed)        AS non_completed_orders
  FROM {{ ref('fact_sales') }}
  GROUP BY customer_id
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

    -- Recency : jours depuis la dernière commande
    DATEDIFF('day', last_order_date, CURRENT_DATE) AS days_since_last_order,

    -- Segmentation client (simplifié RFM)
    CASE
      WHEN total_orders = 1                                          THEN 'one-time'
      WHEN total_orders <= 3 AND lifetime_value < 500               THEN 'occasional'
      WHEN total_orders > 3 AND lifetime_value >= 500               THEN 'loyal'
      WHEN lifetime_value >= 2000                                    THEN 'vip'
      ELSE                                                            'regular'
    END AS customer_segment,

    -- Taux de complétion des commandes
    ROUND(completed_orders / NULLIF(total_orders, 0) * 100, 2) AS completion_rate_pct

  FROM customer_orders
)

SELECT * FROM rfm
