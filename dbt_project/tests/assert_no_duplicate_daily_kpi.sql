-- Checks uniqueness of the grain (order_date, country) in sales_daily_kpi.
-- Fails if any duplicates exist on the composite key.
SELECT
    order_date,
    country,
    COUNT(*) AS row_count
FROM {{ ref('sales_daily_kpi') }}
GROUP BY order_date, country
HAVING COUNT(*) > 1
