-- Vérifie que chaque customer_id présent dans fact_sales
-- a bien une ligne correspondante dans agg_customers (pas de client orphelin).
SELECT DISTINCT f.customer_id
FROM {{ ref('fact_sales') }} f
LEFT JOIN {{ ref('agg_customers') }} a USING (customer_id)
WHERE a.customer_id IS NULL
