-- Checks that every customer_id present in fact_sales
-- has a corresponding row in agg_customers (no orphan customers).
SELECT DISTINCT f.customer_id
FROM {{ ref('fact_sales') }} f
LEFT JOIN {{ ref('agg_customers') }} a USING (customer_id)
WHERE a.customer_id IS NULL
