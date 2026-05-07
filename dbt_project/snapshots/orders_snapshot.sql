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

-- SCD Type 2 sur les commandes.
-- Capture chaque changement de statut ou de montant avec dbt_valid_from / dbt_valid_to.
-- Permet de retrouver l'état d'une commande à n'importe quelle date passée.
SELECT
    order_id,
    customer_id,
    order_date,
    amount,
    status,
    country
FROM {{ source('raw', 'ORDERS') }}

{% endsnapshot %}
