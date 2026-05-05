# Modern Data Stack : Terraform + Snowflake + dbt + Airflow

An end-to-end data pipeline for sales analytics, built with the Modern Data Stack. It starts from a raw CSV file and delivers business KPIs in Snowflake, fully automated and reproducible.

---

## Technologies & Their Roles

### 1. Terraform - Infrastructure as Code
**Role:** provisions all Snowflake resources before anything else runs.

What it creates:
- Database: `DWH`
- Schemas: `RAW`, `STAGING`, `MARTS`
- Compute warehouse: `TRANSFORM_WH` (XSMALL, auto-suspend 60s)

> Without Terraform, you would create all of this manually in the Snowflake UI. Here it is versioned, reproducible, and deployable with a single command.

---

### 2. Snowflake - Cloud Data Warehouse
**Role:** stores and computes data. Organized into 3 layers:

| Schema | Content | Populated by |
|---|---|---|
| `RAW` | `ORDERS` - raw CSV data, never modified | Python script |
| `STAGING` | `stg_orders` - cleaned, filtered (non-null order_id) | dbt (view) |
| `MARTS` | `fact_sales`, `sales_daily_kpi` - ready for analysis | dbt (table) |

---

### 3. dbt - ELT Transformation
**Role:** transforms data already in Snowflake using SQL only.

Model dependency flow:

```
RAW.ORDERS
   └── stg_orders.sql        → filters invalid rows             (STAGING, view)
         └── fact_sales.sql  → keeps completed orders only      (MARTS, table)
               └── sales_daily_kpi.sql → aggregates by date/country  (MARTS, table)
```

Also runs **data quality tests**: `order_id` must be unique and not null.

#### dbt Models in Detail

**`fact_sales`** - The central fact table

Filters raw orders and keeps only **completed** ones, discarding cancelled or pending orders:

```sql
SELECT order_id, customer_id, order_date, amount, status, country
FROM stg_orders
WHERE status = 'completed'
```

**`sales_daily_kpi`** — The business aggregation

Built on top of `fact_sales`, it answers the core business question: **how much did we sell, where, and when?**

```sql
SELECT
  order_date,
  country,
  COUNT(DISTINCT order_id) AS total_orders,
  SUM(amount)              AS revenue
FROM fact_sales
GROUP BY order_date, country
```

| Model | Grain | Business question |
|---|---|---|
| `fact_sales` | 1 row = 1 completed order | Which orders are valid? |
| `sales_daily_kpi` | 1 row = 1 day + 1 country | What is the revenue by date and country? |

---

### 4. Airflow — Orchestration
**Role:** schedules and chains all steps automatically every day.

DAG `snowflake_dbt_pipeline`:
```
load_orders_to_raw  →  dbt run  →  dbt test
```
Runs inside Docker using a custom image with dbt pre-installed.

---

## Execution Flow

```
┌─────────────────────────────────────────────────────────┐
│  1. TERRAFORM (once)                                    │
│     terraform apply → creates DWH, RAW, STAGING,        │
│                        MARTS, TRANSFORM_WH in Snowflake │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│  2. AIRFLOW (every day at midnight)                     │
│                                                         │
│   ┌─────────────────────┐                               │
│   │ load_orders_to_raw  │  Python reads orders.csv      │
│   │                     │  → INSERT into DWH.RAW.ORDERS │
│   └──────────┬──────────┘                               │
│              │                                          │
│   ┌──────────▼──────────┐                               │
│   │      dbt run        │  stg_orders  (STAGING)        │
│   │                     │  fact_sales  (MARTS)           │
│   │                     │  sales_daily_kpi (MARTS)      │
│   └──────────┬──────────┘                               │
│              │                                          │
│   ┌──────────▼──────────┐                               │
│   │      dbt test       │  checks uniqueness & not null │
│   └─────────────────────┘                               │
└─────────────────────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│  3. RESULT in Snowflake                                 │
│     DWH.MARTS.SALES_DAILY_KPI                           │
│     → revenue by date and country, ready for BI         │
└─────────────────────────────────────────────────────────┘
```

**In short:** Terraform = foundations, Snowflake = storage/compute, dbt = transformation, Airflow = orchestrator.

---

## Project Structure

```
.
├── terraform/              # Snowflake infrastructure (IaC)
│   ├── main.tf
│   ├── variables.tf
│   ├── providers.tf
│   └── makefile
├── dbt_project/            # SQL transformations
│   ├── models/
│   │   ├── staging/
│   │   │   └── stg_orders.sql
│   │   └── marts/
│   │       ├── fact_sales.sql
│   │       └── sales_daily_kpi.sql
│   ├── macros/
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

### 1. Provision infrastructure
```bash
cd terraform
make apply-dev
```

### 2. Start Airflow
```bash
docker compose build
docker compose up -d
```
Open `http://localhost:8090` - login: `admin` / `admin`

### 3. Trigger the pipeline
Enable and trigger the `snowflake_dbt_pipeline` DAG from the Airflow UI.
