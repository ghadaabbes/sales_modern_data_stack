-- Vérifie que le revenue_running_total est strictement croissant par pays.
-- Un running total qui diminue révèle une erreur dans la window function ou des données incohérentes.
WITH lagged AS (
    SELECT
        order_date,
        country,
        revenue_running_total,
        LAG(revenue_running_total) OVER (
            PARTITION BY country
            ORDER BY order_date
        ) AS prev_running_total
    FROM {{ ref('sales_daily_kpi') }}
)
SELECT
    order_date,
    country,
    prev_running_total,
    revenue_running_total
FROM lagged
WHERE prev_running_total IS NOT NULL
  AND revenue_running_total < prev_running_total
