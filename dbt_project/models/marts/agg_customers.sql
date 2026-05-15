{{
  config(
    materialized='incremental',
    unique_key='customer_id',
    on_schema_change='sync_all_columns',
    tags=['marts', 'customers']
  )
}}

{% if is_incremental() %}

WITH updated_customers AS (
  SELECT DISTINCT customer_id
  FROM {{ ref('fact_sales') }}
  WHERE order_date >= (
    SELECT DATEADD('day', -3, MAX(last_order_date)) FROM {{ this }}
  )
),

{% else %}

WITH updated_customers AS (
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
    -- Join dim_status to get is_completed flag
    SUM(s.is_completed)                                   AS completed_orders,
    COUNT(DISTINCT f.order_id) - SUM(s.is_completed)      AS non_completed_orders
  FROM {{ ref('fact_sales') }} f
  JOIN {{ ref('dim_status') }} s USING (status)
  WHERE f.customer_id IN (SELECT customer_id FROM updated_customers)
  GROUP BY f.customer_id
),

rfm AS (
  SELECT
    co.customer_id,
    -- Join dim_customer to get country
    dc.country,
    co.total_orders,
    co.lifetime_value,
    co.avg_order_value,
    co.first_order_date,
    co.last_order_date,
    co.customer_lifespan_days,
    co.completed_orders,
    co.non_completed_orders,

    DATEDIFF('day', co.last_order_date, CURRENT_DATE) AS days_since_last_order,

    CASE
      WHEN co.total_orders = 1                                    THEN 'one-time'
      WHEN co.total_orders <= 3 AND co.lifetime_value < 500       THEN 'occasional'
      WHEN co.total_orders > 3  AND co.lifetime_value >= 500      THEN 'loyal'
      WHEN co.lifetime_value >= 2000                              THEN 'vip'
      ELSE                                                             'regular'
    END AS customer_segment,

    ROUND(co.completed_orders / NULLIF(co.total_orders, 0) * 100, 2) AS completion_rate_pct

  FROM customer_orders co
  JOIN {{ ref('dim_customer') }} dc USING (customer_id)
)

SELECT * FROM rfm
