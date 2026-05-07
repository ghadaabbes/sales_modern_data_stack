{{
  config(
    materialized='table',
    tags=['marts', 'kpi']
  )
}}

WITH base AS (
  SELECT
    order_date,
    country,
    COUNT(DISTINCT order_id)  AS total_orders,
    SUM(amount)               AS revenue,
    AVG(amount)               AS avg_order_value,
    SUM(is_completed)         AS completed_orders
  FROM {{ ref('fact_sales') }}
  GROUP BY order_date, country
),

with_windows AS (
  SELECT
    order_date,
    country,
    total_orders,
    revenue,
    avg_order_value,
    completed_orders,

    -- Cumulative revenue per country (running total)
    SUM(revenue) OVER (
      PARTITION BY country
      ORDER BY order_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS revenue_running_total,

    -- Previous day revenue (same country)
    LAG(revenue) OVER (
      PARTITION BY country
      ORDER BY order_date
    ) AS revenue_prev_day,

    -- Previous day order count
    LAG(total_orders) OVER (
      PARTITION BY country
      ORDER BY order_date
    ) AS orders_prev_day,

    -- Country ranking by revenue for the day
    RANK() OVER (
      PARTITION BY order_date
      ORDER BY revenue DESC
    ) AS country_revenue_rank

  FROM base
)

SELECT
  order_date,
  country,
  total_orders,
  revenue,
  avg_order_value,
  completed_orders,
  revenue_running_total,
  revenue_prev_day,
  orders_prev_day,
  country_revenue_rank,

  -- Day-over-day revenue growth (%)
  ROUND(
    (revenue - revenue_prev_day) / NULLIF(revenue_prev_day, 0) * 100,
    2
  ) AS revenue_growth_pct,

  -- Day-over-day order count growth (%)
  ROUND(
    (total_orders - orders_prev_day) / NULLIF(orders_prev_day, 0) * 100,
    2
  ) AS orders_growth_pct

FROM with_windows
