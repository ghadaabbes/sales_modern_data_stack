# Modern Data Stack — Terraform + Snowflake + dbt + Airflow

End-to-end data pipeline for sales analytics. Starts from a raw CSV file and delivers business KPIs in Snowflake, fully automated and reproducible.

---

## Technologies

| Tool | Role |
|------|------|
| **Terraform** | Infrastructure as Code — provisions Snowflake resources |
| **Snowflake** | Cloud data warehouse — storage and compute |
| **dbt** | ELT transformations — versioned, tested, documented SQL |
| **Airflow** | Orchestration — schedules and chains all steps |

---

## dbt Architecture — 3 layers

```
RAW.ORDERS (Snowflake)
 └── stg_orders              [STAGING · view]   cleaning, filtering
       └── int_orders_enriched [STAGING · view]   time dimensions, segmentation
             ├── fact_sales        [MARTS · table]  central fact table
             │     ├── agg_customers     [MARTS · table]  LTV, RFM customer segmentation
             │     └── sales_daily_kpi   [MARTS · table]  daily KPIs, window functions
             └── orders_snapshot   [SNAPSHOTS]      SCD Type 2 on status + amount
```

### Models in detail

| Model | Layer | Grain | Description |
|-------|-------|-------|-------------|
| `stg_orders` | Staging | 1 order | Cleaning and filtering from RAW.ORDERS |
| `int_orders_enriched` | Intermediate | 1 order | `order_year/month/quarter`, `day_of_week`, `amount_bucket`, `is_completed` |
| `fact_sales` | Marts | 1 order | Enriched fact table, base for all marts |
| `agg_customers` | Marts | 1 customer | LTV, avg order value, RFM segment, completion rate |
| `sales_daily_kpi` | Marts | (date, country) | Revenue, running total, day-over-day growth, country ranking |

### SCD Type 2 Snapshot

`orders_snapshot` — tracks every change of `status` or `amount` with `dbt_valid_from` / `dbt_valid_to`.

---

## Data Quality Tests

### Generic tests (schema.yml)
- `not_null`, `unique`, `accepted_values` on all key columns
- `dbt_expectations.expect_column_values_to_be_between` on amounts
- `dbt_expectations.expect_column_values_to_be_of_type` on dates

### Singular tests (tests/)

| Test | What it checks |
|------|----------------|
| `assert_no_duplicate_daily_kpi` | Unique grain `(order_date, country)` in `sales_daily_kpi` |
| `assert_revenue_positive` | No negative amounts in `fact_sales` |
| `assert_ltv_equals_sum_of_orders` | LTV consistency between `agg_customers` and `fact_sales` |
| `assert_running_total_monotonic` | `revenue_running_total` always increasing per country |
| `assert_all_customers_in_agg` | No orphan customers between `fact_sales` and `agg_customers` |

### Source freshness
Automatic monitoring of `RAW.ORDERS`:
- **Warning** if no new data for 24h
- **Error** if no new data for 48h

---

## dbt Environments

The project supports two targets configured in `profiles.yml` via environment variables.

| Variable | Required | Default |
|----------|----------|---------|
| `DBT_SNOWFLAKE_PASSWORD` | Yes | — |
| `DBT_SNOWFLAKE_ACCOUNT` | No | `GOERPYE-DR90600` |
| `DBT_SNOWFLAKE_USER` | No | `GHADAAB` |
| `DBT_SNOWFLAKE_ROLE` | No | `ACCOUNTADMIN` (dev) / `TRANSFORMER` (prod) |
| `DBT_SNOWFLAKE_DATABASE` | No | `DWH` |
| `DBT_SNOWFLAKE_WAREHOUSE` | No | `TRANSFORM_WH` |

```powershell
# Dev (default)
dbt run

# Prod (CI/CD)
dbt run --target prod
```

| Parameter | dev | prod |
|-----------|-----|------|
| Role | `ACCOUNTADMIN` | `TRANSFORMER` |
| Threads | 4 | 8 |
| Default target | Yes | No |

---

## Snowflake Schemas

| Schema | Content | Populated by |
|--------|---------|--------------|
| `RAW` | `ORDERS` — raw CSV data | Python script |
| `STAGING` | `stg_orders`, `int_orders_enriched` | dbt (views) |
| `MARTS` | `fact_sales`, `agg_customers`, `sales_daily_kpi` | dbt (tables) |
| `SNAPSHOTS` | `orders_snapshot` | dbt snapshot |

---

## Execution Flow

```
┌─────────────────────────────────────────────────────────────┐
│  1. TERRAFORM (once)                                        │
│     terraform apply → DWH, RAW, STAGING, MARTS, SNAPSHOTS  │
│                        TRANSFORM_WH, TRANSFORMER role       │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│  2. AIRFLOW (every night at midnight)                       │
│                                                             │
│   load_orders_to_raw → dbt run → dbt snapshot → dbt test   │
│                                                             │
│   dbt run builds in order:                                  │
│     stg_orders → int_orders_enriched                        │
│       → fact_sales → agg_customers                          │
│                    → sales_daily_kpi                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
.
├── terraform/                      # Snowflake infrastructure (IaC)
│   ├── main.tf                     # Resources: DB, schemas, warehouse, roles, grants
│   ├── variables.tf
│   ├── variables.dev.tfvars        # Dev values (gitignored)
│   ├── variables.prod.tfvars       # Prod values
│   ├── providers.tf
│   └── makefile
├── dbt_project/                    # SQL transformations
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
│   ├── tests/                      # Cross-model singular tests
│   │   ├── assert_no_duplicate_daily_kpi.sql
│   │   ├── assert_revenue_positive.sql
│   │   ├── assert_ltv_equals_sum_of_orders.sql
│   │   ├── assert_running_total_monotonic.sql
│   │   └── assert_all_customers_in_agg.sql
│   ├── docs/
│   │   └── overview.md             # dbt doc blocks
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

## Getting Started

### 1. Set environment variables (PowerShell)

```powershell
$env:DBT_SNOWFLAKE_PASSWORD    = "your_password"
$env:SNOWFLAKE_PASSWORD        = "your_password"
$env:TF_VAR_snowflake_password = "your_password"
```

> To avoid retyping every session, add these lines to `notepad $PROFILE`.

### 2. Copy profiles.yml to ~/.dbt/

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.dbt"
Copy-Item "dbt_project\profiles.yml" "$env:USERPROFILE\.dbt\profiles.yml"
```

### 3. Provision Snowflake infrastructure (once)

```powershell
# make is not available on Windows — use terraform directly
Set-Location terraform
terraform init
terraform apply "-var-file=variables.dev.tfvars" -auto-approve
Set-Location ..
```

### 4. Load raw data (required before dbt run)

```powershell
python scripts/load_orders_to_raw.py
# → [OK] 6 rows loaded into DWH.RAW.ORDERS
```

> This step is mandatory before `dbt run` — dbt reads from `RAW.ORDERS`.

### 5. Install dbt packages and build models

```powershell
Set-Location dbt_project
dbt deps        # install dbt-utils + dbt-expectations
dbt run         # create all tables/views in Snowflake
dbt snapshot    # create orders_snapshot (SCD Type 2)
dbt test        # run all quality tests
```

### 6. Start Airflow

```powershell
docker compose build
docker compose up -d
```
Open `http://localhost:8090` — login: `admin` / `admin`

Enable and trigger the `snowflake_dbt_pipeline` DAG from the UI.

### 7. Browse dbt documentation locally

```powershell
dbt docs generate
dbt docs serve
# → http://localhost:8080
```

---

## When to Run What

| You change | You run |
|------------|---------|
| A SQL model (`*.sql`) | `dbt run` |
| A single model | `dbt run -s model_name` |
| A model and its dependants | `dbt run -s +model_name` |
| Tests (`schema.yml`, `tests/`) | `dbt test` |
| Snapshot | `dbt snapshot` |
| `packages.yml` | `dbt deps` then `dbt run` |
| New Snowflake schema / role / warehouse | `terraform apply` |
| Python script or Airflow DAG | Nothing — Airflow handles it in prod |

> **Rule**: Terraform = infrastructure, dbt = data, Airflow = automation.

---

## Useful dbt Commands

```powershell
# Build all models (dev by default)
dbt run

# Build in prod
dbt run --target prod

# Target a single model and its dependencies
dbt run -s +fact_sales

# Run all tests (generic + singular)
dbt test

# Check source freshness
dbt source freshness

# Run SCD Type 2 snapshot
dbt snapshot

# Interactive documentation
dbt docs generate; dbt docs serve
```
