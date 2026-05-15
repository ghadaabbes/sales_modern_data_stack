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

## dbt Architecture — Star Schema + CDC

```
RAW.ORDERS (Snowflake base table)
 │
 ├── ORDERS_STREAM (Snowflake CDC Stream)
 │       └── stg_orders_cdc      [STAGING · stream_merge]  real MERGE via CDC
 │
 └── stg_orders                  [STAGING · view]   cleaning, filtering
       └── int_orders_enriched   [STAGING · view]   time dimensions, segmentation
             │
             ├── dim_customer    [MARTS · table]    customer_id, country
             ├── dim_date        [MARTS · table]    order_date, year, month, quarter…
             ├── dim_status      [MARTS · table]    status, is_completed
             ├── dim_amount_bucket [MARTS · table]  amount_bucket, min/max thresholds
             │
             └── fact_sales      [MARTS · incremental]  FK only + amount
                   ├── agg_customers   [MARTS · incremental]  LTV, RFM (joins dims)
                   └── sales_daily_kpi [MARTS · incremental]  KPIs, window functions (joins dims)

orders_snapshot                  [SNAPSHOTS]        SCD Type 2 on status + amount
```

### Star schema

```
         dim_customer          dim_date
        (customer_id PK        (order_date PK
         country)               year, month
              │                 quarter, week)
              │ FK                    │ FK
              └──────┐  ┌────────────┘
                     ▼  ▼
                   fact_sales
                   (order_id PK
                    customer_id FK
                    order_date  FK
                    status      FK
                    amount_bucket FK
                    amount ← only metric)
                     ▲  ▲
              ┌──────┘  └────────────┐
              │ FK                   │ FK
         dim_status             dim_amount_bucket
        (status PK              (amount_bucket PK
         is_completed)           min_amount, max_amount)
```

### Models in detail

| Model | Type | Materialization | Grain | Description |
|-------|------|-----------------|-------|-------------|
| `stg_orders` | Staging | view | 1 order | Cleaning and filtering from RAW.ORDERS |
| `stg_orders_cdc` | Staging | **stream_merge** | 1 order | Real CDC via Snowflake Stream + MERGE |
| `int_orders_enriched` | Intermediate | view | 1 order | Time dimensions, `amount_bucket`, `is_completed` |
| `dim_customer` | Dimension | table | 1 customer | `customer_id`, `country` |
| `dim_date` | Dimension | table | 1 date | Date attributes: year, month, quarter, week |
| `dim_status` | Dimension | table | 1 status | `status`, `is_completed` flag |
| `dim_amount_bucket` | Dimension | table | 1 bucket | Bucket label + min/max thresholds |
| `fact_sales` | Fact | **incremental** | 1 order | FK only + `amount` — 3-day lookback |
| `agg_customers` | Aggregate | **incremental** | 1 customer | LTV, RFM — joins `dim_customer`, `dim_status` |
| `sales_daily_kpi` | Aggregate | **incremental** | (date, country) | KPIs + window functions — joins dims |

### Incremental strategy per model

| Model | unique_key | Strategy |
|-------|------------|----------|
| `fact_sales` | `order_id` | 3-day lookback — handles late-arriving data |
| `agg_customers` | `customer_id` | Recomputes only customers with recent activity, full history for LTV |
| `sales_daily_kpi` | `(order_date, country)` | Union `{{ this }}` + new rows — window functions always see full history |

### Referential integrity tests (relationships)

```yaml
fact_sales.customer_id   → dim_customer.customer_id
fact_sales.order_date    → dim_date.order_date
fact_sales.status        → dim_status.status
fact_sales.amount_bucket → dim_amount_bucket.amount_bucket
```

### CDC Pipeline (Snowflake Stream + MERGE)

`stg_orders_cdc` uses a **custom `stream_merge` materialization** backed by `DWH.RAW.ORDERS_STREAM`:

| Stream event | MERGE action |
|-------------|--------------|
| `METADATA$ACTION = 'INSERT'` + `ISUPDATE = FALSE` | `INSERT` new row |
| `METADATA$ACTION = 'INSERT'` + `ISUPDATE = TRUE` | `UPDATE SET` existing row |
| `METADATA$ACTION = 'DELETE'` + `ISUPDATE = FALSE` | `DELETE` row |

Metadata columns added automatically: `_cdc_action`, `_loaded_at`.

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
│     stg_orders_cdc (CDC stream MERGE)                       │
│     stg_orders → int_orders_enriched                        │
│       → fact_sales (incremental)                            │
│           → agg_customers (incremental)                     │
│           → sales_daily_kpi (incremental)                   │
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
│   │   │   ├── stg_orders_cdc.sql      # CDC model — stream_merge materialization
│   │   │   └── schema.yml              # sources + tests + freshness + CDC doc
│   │   ├── intermediate/
│   │   │   ├── int_orders_enriched.sql
│   │   │   └── schema.yml
│   │   └── marts/
│   │       ├── fact_sales.sql          # incremental (unique_key: order_id)
│   │       ├── agg_customers.sql       # incremental (unique_key: customer_id)
│   │       ├── sales_daily_kpi.sql     # incremental (unique_key: order_date+country)
│   │       └── schema.yml
│   ├── snapshots/
│   │   └── orders_snapshot.sql         # SCD Type 2
│   ├── tests/                          # Cross-model singular tests
│   │   ├── assert_no_duplicate_daily_kpi.sql
│   │   ├── assert_revenue_positive.sql
│   │   ├── assert_ltv_equals_sum_of_orders.sql
│   │   ├── assert_running_total_monotonic.sql
│   │   └── assert_all_customers_in_agg.sql
│   ├── docs/
│   │   └── overview.md                 # dbt doc blocks
│   ├── macros/
│   │   ├── generate_schema_name.sql
│   │   └── materializations/
│   │       └── stream_merge.sql        # custom CDC materialization (Stream + MERGE)
│   ├── packages.yml                    # dbt-utils + dbt-expectations
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
dbt deps                    # install dbt-utils + dbt-expectations
dbt run --full-refresh      # first run: full load of all models (required)
dbt snapshot                # create orders_snapshot (SCD Type 2)
dbt test                    # run all quality tests
```

> **Important**: incremental models (`fact_sales`, `agg_customers`, `sales_daily_kpi`, `stg_orders_cdc`)
> require `--full-refresh` on the very first run to create the target tables.
> Subsequent daily runs use `dbt run` (no flag) to process only deltas.

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
| An incremental model schema (new column) | `dbt run -s model_name --full-refresh` |
| Tests (`schema.yml`, `tests/`) | `dbt test` |
| Snapshot | `dbt snapshot` |
| `packages.yml` | `dbt deps` then `dbt run` |
| New Snowflake schema / role / warehouse / stream | `terraform apply` |
| Python script or Airflow DAG | Nothing — Airflow handles it in prod |

> **Rule**: Terraform = infrastructure, dbt = data, Airflow = automation.

---

## Useful dbt Commands

```powershell
# ── First run (mandatory) ─────────────────────────────────────────────────────
dbt run --full-refresh          # full load of all models, creates incremental tables

# ── Daily runs (incremental — deltas only) ────────────────────────────────────
dbt run                         # process only new/changed data
dbt run --target prod           # same in prod (uses TRANSFORMER role, 8 threads)

# ── Targeting specific models ─────────────────────────────────────────────────
dbt run -s stg_orders_cdc       # run CDC model only (reads from ORDERS_STREAM)
dbt run -s +fact_sales          # fact_sales and all its upstream dependencies
dbt run -s fact_sales+          # fact_sales and all downstream models

# ── Schema changes on incremental models ─────────────────────────────────────
dbt run -s fact_sales --full-refresh      # rebuild from scratch after adding a column

# ── Quality and observability ─────────────────────────────────────────────────
dbt test                        # run all tests (generic + singular)
dbt source freshness            # check RAW.ORDERS data recency
dbt snapshot                    # run SCD Type 2 (orders_snapshot)

# ── Documentation ─────────────────────────────────────────────────────────────
dbt docs generate; dbt docs serve   # → http://localhost:8080
```
