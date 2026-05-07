-- Checks that no order has a negative amount in fact_sales.
-- A negative amount would indicate an ingestion error or a badly coded refund.
SELECT
    order_id,
    amount
FROM {{ ref('fact_sales') }}
WHERE amount < 0
