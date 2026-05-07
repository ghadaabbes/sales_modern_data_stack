{% snapshot orders_snapshot %}

{{
    config(
        target_schema='SNAPSHOTS',
        unique_key='order_id',
        strategy='check',
        check_cols=['status', 'amount'],
        invalidate_hard_deletes=True
    )
}}

-- SCD Type 2 on orders.
-- Captures every change of status or amount with dbt_valid_from / dbt_valid_to.
-- Allows querying the state of any order at any past date.
SELECT
    order_id,
    customer_id,
    order_date,
    amount,
    status,
    country
FROM {{ source('raw', 'ORDERS') }}

{% endsnapshot %}
