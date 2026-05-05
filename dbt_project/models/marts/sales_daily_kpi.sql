SELECT
  order_date,
  country,
  COUNT(DISTINCT order_id) AS total_orders,
  SUM(amount) AS revenue
FROM {{ ref('fact_sales') }}
GROUP BY order_date, country