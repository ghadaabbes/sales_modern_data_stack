SELECT
  order_id,
  customer_id,
  order_date,
  amount,
  status,
  country
FROM {{ source('raw', 'ORDERS') }}
WHERE order_id IS NOT NULL