{% docs __overview__ %}

# Sales Modern Data Stack — Documentation dbt

## Architecture

Ce projet suit une architecture **layered dbt** en 3 couches :

```
RAW (Snowflake)
 └── staging       → nettoyage, typage, filtrages simples
       └── intermediate  → enrichissements, champs dérivés
             └── marts         → agrégations métier, KPIs, tables analytiques
```

## Modèles

| Couche       | Modèle                  | Matérialisation | Description courte                          |
|-------------|-------------------------|-----------------|---------------------------------------------|
| Staging     | `stg_orders`            | View            | Commandes nettoyées depuis RAW.ORDERS       |
| Intermediate| `int_orders_enriched`   | View            | Commandes avec dimensions temporelles et segmentation |
| Marts       | `fact_sales`            | Table           | Table de faits des ventes                   |
| Marts       | `agg_customers`         | Table           | Agrégation client avec LTV et segmentation RFM |
| Marts       | `sales_daily_kpi`       | Table           | KPIs journaliers avec window functions      |

## Snapshots

| Snapshot          | Stratégie | Colonnes trackées      |
|-------------------|-----------|------------------------|
| `orders_snapshot` | check     | `status`, `amount`     |

Le snapshot capture chaque changement de statut ou de montant (SCD Type 2) avec `dbt_valid_from` / `dbt_valid_to`.

## Tests

### Tests génériques (schema.yml)
- `not_null`, `unique`, `accepted_values`
- `dbt_expectations.expect_column_values_to_be_between`
- `dbt_expectations.expect_column_values_to_be_of_type`

### Tests singuliers (tests/)
| Fichier                               | Ce qu'il vérifie                                         |
|---------------------------------------|----------------------------------------------------------|
| `assert_no_duplicate_daily_kpi`       | Unicité du grain (order_date, country)                   |
| `assert_revenue_positive`             | Aucun montant négatif dans fact_sales                    |
| `assert_ltv_equals_sum_of_orders`     | Cohérence LTV entre agg_customers et fact_sales          |
| `assert_running_total_monotonic`      | Revenue running total strictement croissant              |
| `assert_all_customers_in_agg`         | Aucun client orphelin entre fact_sales et agg_customers  |

## Source freshness

La source `raw.ORDERS` est surveillée :
- **Warning** si pas de nouvelle commande depuis 24h
- **Erreur** si pas de nouvelle commande depuis 48h

{% enddocs %}


{% docs source_raw %}
Couche de données brutes ingérées depuis le système transactionnel.
Aucune transformation n'est appliquée à ce niveau — les données sont chargées telles quelles dans Snowflake (schéma RAW).
{% enddocs %}


{% docs stg_orders %}
Commandes nettoyées et standardisées depuis `RAW.ORDERS`.

Transformations appliquées :
- Suppression des lignes sans `order_id`
- Aucune agrégation ni enrichissement (délégué à la couche intermediate)

Grain : **1 ligne par commande**.
{% enddocs %}


{% docs int_orders_enriched %}
Enrichissement des commandes avec dimensions temporelles et segmentation.

Champs dérivés ajoutés :
- `order_year`, `order_month`, `order_quarter` — via `DATE_TRUNC`
- `day_of_week`, `week_of_year` — pour analyses temporelles fines
- `amount_bucket` — segmentation : small / medium / large / premium
- `is_completed` — flag binaire pour les KPIs de taux de complétion

Grain : **1 ligne par commande**.
{% enddocs %}


{% docs fact_sales %}
Table de faits centrale du projet. Expose toutes les colonnes de `int_orders_enriched`
dans un format stable pour les marts analytiques.

Grain : **1 ligne par commande**.
{% enddocs %}


{% docs agg_customers %}
Agrégation par client avec métriques de valeur et segmentation RFM simplifiée.

Segmentation `customer_segment` :
- `one-time` — 1 seule commande
- `occasional` — 2-3 commandes, LTV < 500€
- `regular` — autres
- `loyal` — >3 commandes et LTV ≥ 500€
- `vip` — LTV ≥ 2000€

Grain : **1 ligne par `customer_id`**.
{% enddocs %}


{% docs sales_daily_kpi %}
KPIs de vente agrégés par jour et par pays, enrichis de window functions :

- `revenue_running_total` — cumul depuis le début de l'historique
- `revenue_growth_pct` — croissance J vs J-1
- `orders_growth_pct` — croissance des commandes J vs J-1
- `country_revenue_rank` — classement des pays par revenue sur la journée

Grain : **1 ligne par (`order_date`, `country`)**.
{% enddocs %}
