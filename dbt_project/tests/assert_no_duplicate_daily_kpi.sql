-- Vérifie l'unicité du grain (order_date, country) dans sales_daily_kpi.
-- Ce test échoue si des doublons existent sur la clé composite.
SELECT
    order_date,
    country,
    COUNT(*) AS row_count
FROM {{ ref('sales_daily_kpi') }}
GROUP BY order_date, country
HAVING COUNT(*) > 1
