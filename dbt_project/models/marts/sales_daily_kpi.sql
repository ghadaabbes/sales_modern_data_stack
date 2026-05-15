{{
  config(
    materialized='incremental',
    unique_key=['order_date', 'country'],
    on_schema_change='sync_all_columns',
    tags=['marts', 'kpi']
  )
}}

{% if is_incremental() %}

WITH cutoff AS (
  SELECT DATEADD('day', -3, MAX(order_date)) AS cutoff_date
  FROM {{ this }}
),

new_base AS (
  SELECT
    f.order_date,
    dc.country,                          -- from dim_customer (star join)
    COUNT(DISTINCT f.order_id)           AS total_orders,
    SUM(f.amount)                        AS revenue,
    AVG(f.amount)                        AS avg_order_value,
    SUM(ds.is_completed)                 AS completed_orders  -- from dim_status (star join)
  FROM {{ ref('fact_sales') }}    f
  JOIN {{ ref('dim_customer') }}  dc USING (customer_id)
  JOIN {{ ref('dim_status') }}    ds USING (status)
  WHERE f.order_date >= (SELECT cutoff_date FROM cutoff)
  GROUP BY f.order_date, dc.country
),

full_history AS (
  SELECT order_date, country, total_orders, revenue, avg_order_value, completed_orders
  FROM {{ this }}
  WHERE order_date < (SELECT cutoff_date FROM cutoff)

  UNION ALL

  SELECT * FROM new_base
),

{% else %}

WITH new_base AS (
  SELECT
    f.order_date,
    dc.country,
    COUNT(DISTINCT f.order_id)  AS total_orders,
    SUM(f.amount)               AS revenue,
    AVG(f.amount)               AS avg_order_value,
    SUM(ds.is_completed)        AS completed_orders
  FROM {{ ref('fact_sales') }}   f
  JOIN {{ ref('dim_customer') }} dc USING (customer_id)
  JOIN {{ ref('dim_status') }}   ds USING (status)
  GROUP BY f.order_date, dc.country
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

    SUM(revenue) OVER (
      PARTITION BY country
      ORDER BY order_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS revenue_running_total,

    LAG(revenue) OVER (
      PARTITION BY country ORDER BY order_date
    ) AS revenue_prev_day,

    LAG(total_orders) OVER (
      PARTITION BY country ORDER BY order_date
    ) AS orders_prev_day,

    RANK() OVER (
      PARTITION BY order_date ORDER BY revenue DESC
    ) AS country_revenue_rank

  FROM full_history
),

final AS (
  SELECT
    *,
    ROUND((revenue - revenue_prev_day) / NULLIF(revenue_prev_day, 0) * 100, 2) AS revenue_growth_pct,
    ROUND((total_orders - orders_prev_day) / NULLIF(orders_prev_day, 0) * 100, 2) AS orders_growth_pct
  FROM with_windows
)

SELECT * FROM final

{% if is_incremental() %}
WHERE order_date >= (SELECT cutoff_date FROM cutoff)
{% endif %}
