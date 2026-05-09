{{
  config(
    materialized='incremental',
    unique_key=['order_date', 'country'],
    on_schema_change='sync_all_columns',
    tags=['marts', 'kpi']
  )
}}

-- Incremental strategy for window functions:
-- 1. Aggregate only the lookback window from fact_sales (new/updated days)
-- 2. Union with historical rows from {{ this }} to provide full context
-- 3. Compute window functions (running total, LAG, RANK) over full history
-- 4. Return only the lookback window rows so dbt merges just what changed

{% if is_incremental() %}

WITH cutoff AS (
  -- Single reference point to avoid repeating the subquery
  SELECT DATEADD('day', -3, MAX(order_date)) AS cutoff_date
  FROM {{ this }}
),

new_base AS (
  -- Re-aggregate the 3-day lookback window (handles late-arriving data)
  SELECT
    order_date,
    country,
    COUNT(DISTINCT order_id)  AS total_orders,
    SUM(amount)               AS revenue,
    AVG(amount)               AS avg_order_value,
    SUM(is_completed)         AS completed_orders
  FROM {{ ref('fact_sales') }}
  WHERE order_date >= (SELECT cutoff_date FROM cutoff)
  GROUP BY order_date, country
),

full_history AS (
  -- Historical rows outside the lookback window (untouched)
  SELECT order_date, country, total_orders, revenue, avg_order_value, completed_orders
  FROM {{ this }}
  WHERE order_date < (SELECT cutoff_date FROM cutoff)

  UNION ALL

  -- Newly computed rows for the lookback window
  SELECT * FROM new_base
),

{% else %}

WITH new_base AS (
  -- Full refresh: aggregate all historical data
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

full_history AS (
  SELECT * FROM new_base
),

{% endif %}

with_windows AS (
  SELECT
    order_date,
    country,
    total_orders,
    revenue,
    avg_order_value,
    completed_orders,

    -- Cumulative revenue per country — needs full history to be correct
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

  FROM full_history
),

final AS (
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
)

SELECT * FROM final

{% if is_incremental() %}
-- Only merge the lookback window rows back into the table.
-- Historical rows (outside lookback) are already correct and untouched.
WHERE order_date >= (SELECT cutoff_date FROM cutoff)
{% endif %}
