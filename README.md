# Modern Data Stack — Terraform + Snowflake + dbt + Airflow

Pipeline de données end-to-end pour l'analytique commerciale. Part d'un fichier CSV brut et produit des KPIs métier dans Snowflake, entièrement automatisé et reproductible.

---

## Technologies

| Outil | Rôle |
|-------|------|
| **Terraform** | Infrastructure as Code — provisionne Snowflake |
| **Snowflake** | Data warehouse cloud — stockage et compute |
| **dbt** | Transformations ELT — SQL versionné, testé, documenté |
| **Airflow** | Orchestration — planifie et enchaîne les étapes |

---

## Architecture dbt — 3 couches

```
RAW.ORDERS (Snowflake)
 └── stg_orders              [STAGING · view]   nettoyage, filtrage
       └── int_orders_enriched [STAGING · view]   dimensions temporelles, segmentation
             ├── fact_sales        [MARTS · table]  table de faits centrale
             │     ├── agg_customers     [MARTS · table]  LTV, segmentation client (RFM)
             │     └── sales_daily_kpi   [MARTS · table]  KPIs journaliers, window functions
             └── orders_snapshot   [SNAPSHOTS]      SCD Type 2 sur status + amount
```

### Modèles en détail

| Modèle | Couche | Grain | Description |
|--------|--------|-------|-------------|
| `stg_orders` | Staging | 1 commande | Nettoyage et filtrage depuis RAW.ORDERS |
| `int_orders_enriched` | Intermediate | 1 commande | `order_year/month/quarter`, `day_of_week`, `amount_bucket`, `is_completed` |
| `fact_sales` | Marts | 1 commande | Table de faits enrichie, base de tous les marts |
| `agg_customers` | Marts | 1 client | LTV, panier moyen, segment RFM, taux de complétion |
| `sales_daily_kpi` | Marts | (date, pays) | Revenue, running total, croissance J/J-1, ranking pays |

### Snapshot SCD Type 2

`orders_snapshot` — track chaque changement de `status` ou `amount` avec `dbt_valid_from` / `dbt_valid_to`.

---

## Tests qualité

### Tests génériques (schema.yml)
- `not_null`, `unique`, `accepted_values` sur toutes les colonnes clés
- `dbt_expectations.expect_column_values_to_be_between` sur les montants
- `dbt_expectations.expect_column_values_to_be_of_type` sur les dates

### Tests singuliers (tests/)

| Test | Ce qu'il vérifie |
|------|-----------------|
| `assert_no_duplicate_daily_kpi` | Grain unique `(order_date, country)` dans `sales_daily_kpi` |
| `assert_revenue_positive` | Aucun montant négatif dans `fact_sales` |
| `assert_ltv_equals_sum_of_orders` | Cohérence LTV entre `agg_customers` et `fact_sales` |
| `assert_running_total_monotonic` | `revenue_running_total` toujours croissant par pays |
| `assert_all_customers_in_agg` | Aucun client orphelin entre `fact_sales` et `agg_customers` |

### Source freshness
Surveillance automatique de `RAW.ORDERS` :
- **Warning** si pas de nouvelles données depuis 24h
- **Erreur** si pas de nouvelles données depuis 48h

---

## Environnements dbt

Le projet supporte deux cibles configurées dans `profiles.yml` via variables d'environnement.

| Variable | Obligatoire | Défaut |
|----------|-------------|--------|
| `DBT_SNOWFLAKE_PASSWORD` | Oui | — |
| `DBT_SNOWFLAKE_ACCOUNT` | Non | `GOERPYE-DR90600` |
| `DBT_SNOWFLAKE_USER` | Non | `GHADAAB` |
| `DBT_SNOWFLAKE_ROLE` | Non | `ACCOUNTADMIN` (dev) / `TRANSFORMER` (prod) |
| `DBT_SNOWFLAKE_DATABASE` | Non | `DWH` |
| `DBT_SNOWFLAKE_WAREHOUSE` | Non | `TRANSFORM_WH` |

```bash
# Dev (défaut)
dbt run

# Prod (CI/CD)
dbt run --target prod
```

| Paramètre | dev | prod |
|-----------|-----|------|
| Role | `ACCOUNTADMIN` | `TRANSFORMER` |
| Threads | 4 | 8 |
| Target par défaut | Oui | Non |

---

## Schémas Snowflake

| Schéma | Contenu | Alimenté par |
|--------|---------|--------------|
| `RAW` | `ORDERS` — données brutes CSV | Script Python |
| `STAGING` | `stg_orders`, `int_orders_enriched` | dbt (views) |
| `MARTS` | `fact_sales`, `agg_customers`, `sales_daily_kpi` | dbt (tables) |
| `SNAPSHOTS` | `orders_snapshot` | dbt snapshot |

---

## Flux d'exécution

```
┌─────────────────────────────────────────────────────────────┐
│  1. TERRAFORM (une fois)                                    │
│     terraform apply → DWH, RAW, STAGING, MARTS, SNAPSHOTS  │
│                        TRANSFORM_WH                         │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│  2. AIRFLOW (toutes les nuits à minuit)                     │
│                                                             │
│   load_orders_to_raw  →  dbt run  →  dbt test              │
│                                                             │
│   dbt run construit dans l'ordre :                         │
│     stg_orders → int_orders_enriched                       │
│       → fact_sales → agg_customers                         │
│                    → sales_daily_kpi                       │
└─────────────────────────────────────────────────────────────┘
```

---

## Structure du projet

```
.
├── terraform/                      # Infrastructure Snowflake (IaC)
│   ├── main.tf
│   ├── variables.tf
│   ├── providers.tf
│   └── makefile
├── dbt_project/                    # Transformations SQL
│   ├── models/
│   │   ├── staging/
│   │   │   ├── stg_orders.sql
│   │   │   └── schema.yml          # sources + tests + freshness
│   │   ├── intermediate/
│   │   │   ├── int_orders_enriched.sql
│   │   │   └── schema.yml
│   │   └── marts/
│   │       ├── fact_sales.sql
│   │       ├── agg_customers.sql
│   │       ├── sales_daily_kpi.sql
│   │       └── schema.yml
│   ├── snapshots/
│   │   └── orders_snapshot.sql     # SCD Type 2
│   ├── tests/                      # Tests singuliers cross-modèles
│   │   ├── assert_no_duplicate_daily_kpi.sql
│   │   ├── assert_revenue_positive.sql
│   │   ├── assert_ltv_equals_sum_of_orders.sql
│   │   ├── assert_running_total_monotonic.sql
│   │   └── assert_all_customers_in_agg.sql
│   ├── docs/
│   │   └── overview.md             # Doc blocks pour dbt docs
│   ├── macros/
│   │   └── generate_schema_name.sql
│   ├── packages.yml                # dbt-utils + dbt-expectations
│   └── dbt_project.yml
├── airflow/
│   └── dags/
│       └── snowflake_dbt_pipeline.py
├── scripts/
│   └── load_orders_to_raw.py
├── data/
│   └── orders.csv
├── Dockerfile
└── docker-compose.yml
```

---

## Démarrage

### 1. Variables d'environnement

```bash
export DBT_SNOWFLAKE_PASSWORD="ton_mot_de_passe"
# optionnel — surcharger les autres valeurs si besoin
export DBT_SNOWFLAKE_ROLE="ACCOUNTADMIN"
```

### 2. Provisionner l'infrastructure

```bash
cd terraform
make apply-dev
```

### 3. Installer les packages dbt

```bash
cd dbt_project
dbt deps
```

### 4. Lancer Airflow

```bash
docker compose build
docker compose up -d
```
Ouvrir `http://localhost:8090` — login : `admin` / `admin`

### 5. Déclencher le pipeline

Activer et déclencher le DAG `snowflake_dbt_pipeline` depuis l'UI Airflow.

### 6. Consulter la documentation dbt en local

```bash
dbt docs generate
dbt docs serve
# → http://localhost:8080
```

---

## Commandes dbt utiles

```bash
# Construire tous les modèles (dev par défaut)
dbt run

# Construire en prod
dbt run --target prod

# Lancer tous les tests (génériques + singuliers)
dbt test

# Vérifier la fraîcheur de la source
dbt source freshness

# Lancer le snapshot SCD Type 2
dbt snapshot

# Documentation interactive
dbt docs generate && dbt docs serve

# Cibler un seul modèle et ses dépendances
dbt run -s +fact_sales
```
