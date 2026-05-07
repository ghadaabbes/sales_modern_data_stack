-- Vérifie la cohérence cross-modèles : le lifetime_value dans agg_customers
-- doit correspondre exactement à la somme des montants dans fact_sales par client.
WITH expected AS (
    SELECT
        customer_id,
        SUM(amount) AS expected_ltv
    FROM {{ ref('fact_sales') }}
    GROUP BY customer_id
),
actual AS (
    SELECT
        customer_id,
        lifetime_value AS actual_ltv
    FROM {{ ref('agg_customers') }}
)
SELECT
    e.customer_id,
    e.expected_ltv,
    a.actual_ltv,
    ABS(e.expected_ltv - a.actual_ltv) AS delta
FROM expected e
JOIN actual a USING (customer_id)
WHERE ABS(e.expected_ltv - a.actual_ltv) > 0.01
