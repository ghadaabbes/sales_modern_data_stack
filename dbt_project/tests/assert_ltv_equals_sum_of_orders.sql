-- Cross-model consistency check: lifetime_value in agg_customers
-- must exactly match the sum of amounts in fact_sales per customer.
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
