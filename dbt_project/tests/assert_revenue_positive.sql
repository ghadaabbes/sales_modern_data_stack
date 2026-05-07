-- Vérifie qu'aucune commande n'a un montant négatif dans fact_sales.
-- Un montant négatif indiquerait une erreur d'ingestion ou un remboursement mal codé.
SELECT
    order_id,
    amount
FROM {{ ref('fact_sales') }}
WHERE amount < 0
