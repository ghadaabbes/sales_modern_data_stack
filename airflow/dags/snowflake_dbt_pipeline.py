import logging
from datetime import datetime, timedelta

from airflow import DAG
from airflow.models import Variable
from airflow.operators.bash import BashOperator
from airflow.utils.trigger_rule import TriggerRule

DBT_PROJECT_DIR = "/opt/airflow/dbt_project"
SCRIPTS_DIR = "/opt/airflow/scripts"

# dbt target — override via Airflow Variable "dbt_target" to switch to prod
DBT_TARGET = Variable.get("dbt_target", default_var="dev")

# Snowflake credentials injected from Airflow Variables (never hardcoded)
DBT_ENV = {
    "DBT_SNOWFLAKE_PASSWORD":  Variable.get("snowflake_password",  default_var=""),
    "DBT_SNOWFLAKE_ACCOUNT":   Variable.get("snowflake_account",   default_var="GOERPYE-DR90600"),
    "DBT_SNOWFLAKE_USER":      Variable.get("snowflake_user",      default_var="GHADAAB"),
    "DBT_SNOWFLAKE_ROLE":      Variable.get("snowflake_role",      default_var="ACCOUNTADMIN"),
    "DBT_SNOWFLAKE_DATABASE":  Variable.get("snowflake_database",  default_var="DWH"),
    "DBT_SNOWFLAKE_WAREHOUSE": Variable.get("snowflake_warehouse", default_var="TRANSFORM_WH"),
}


def on_failure_callback(context: dict) -> None:
    """Structured failure log — extensible to Slack / PagerDuty."""
    ti = context["task_instance"]
    logging.error(
        "[%s] Task '%s' failed | run_id=%s | log: %s",
        ti.dag_id,
        ti.task_id,
        context["run_id"],
        ti.log_url,
    )
    # To notify Slack, uncomment and configure SlackWebhookOperator here


default_args = {
    "owner": "data-team",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(minutes=30),
    "on_failure_callback": on_failure_callback,
    "email_on_failure": False,
    "email_on_retry": False,
}

with DAG(
    dag_id="snowflake_dbt_pipeline",
    description="Daily ELT pipeline: RAW -> staging -> intermediate -> marts + snapshot + tests + docs",
    default_args=default_args,
    start_date=datetime(2025, 1, 1),
    schedule="@daily",
    catchup=False,
    tags=["snowflake", "dbt", "data-engineering"],
    doc_md="""
## snowflake_dbt_pipeline

Full ELT pipeline — runs every night at midnight.

### Execution flow

```
load_orders_to_raw
    └── dbt_source_freshness
            ├── dbt_snapshot          ← SCD Type 2 in parallel
            └── dbt_run_staging
                    └── dbt_run_intermediate
                            └── dbt_run_marts
                                    └── dbt_test  ← converges snapshot + marts
                                            └── dbt_docs_generate
```

### Airflow Variables to configure
| Variable | Description |
|----------|-------------|
| `dbt_target` | dbt target: `dev` (default) or `prod` |
| `snowflake_password` | Snowflake password |
| `snowflake_account` | Snowflake account identifier |
| `snowflake_role` | Snowflake role (`ACCOUNTADMIN` in dev) |
    """,
) as dag:

    # ─── 1. Load CSV → RAW ────────────────────────────────────────────────────

    load_orders = BashOperator(
        task_id="load_orders_to_raw",
        bash_command=f"python {SCRIPTS_DIR}/load_orders_to_raw.py",
        env=DBT_ENV,
        execution_timeout=timedelta(minutes=15),
        doc_md="Loads `orders.csv` into `DWH.RAW.ORDERS` via the Python script.",
    )

    # ─── 2. Source freshness ──────────────────────────────────────────────────

    source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt source freshness --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        doc_md=(
            "Checks that `RAW.ORDERS` contains recent data.\n"
            "- Warning if > 24h\n"
            "- Error if > 48h"
        ),
    )

    # ─── 3a. SCD Type 2 snapshot (parallel with staging) ─────────────────────

    dbt_snapshot = BashOperator(
        task_id="dbt_snapshot",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt snapshot --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        doc_md=(
            "Runs `orders_snapshot` (SCD Type 2).\n"
            "Captures every change of `status` or `amount` into `SNAPSHOTS`."
        ),
    )

    # ─── 3b. Layer-by-layer transformations ──────────────────────────────────

    dbt_run_staging = BashOperator(
        task_id="dbt_run_staging",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt run --select staging --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        doc_md="Builds `stg_orders` (view) in the STAGING schema.",
    )

    dbt_run_intermediate = BashOperator(
        task_id="dbt_run_intermediate",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt run --select intermediate --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        doc_md=(
            "Builds `int_orders_enriched` — time dimensions "
            "(year, month, quarter, week), `amount_bucket`, `is_completed`."
        ),
    )

    dbt_run_marts = BashOperator(
        task_id="dbt_run_marts",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt run --select marts --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        doc_md=(
            "Builds in parallel in Snowflake:\n"
            "- `fact_sales` — central fact table\n"
            "- `agg_customers` — LTV, RFM segmentation\n"
            "- `sales_daily_kpi` — daily KPIs + window functions"
        ),
    )

    # ─── 4. Quality tests (converges snapshot + marts) ────────────────────────

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt test --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        trigger_rule=TriggerRule.ALL_SUCCESS,
        doc_md=(
            "Runs all tests:\n"
            "- Generic: `not_null`, `unique`, `accepted_values`, `dbt_expectations`\n"
            "- Singular: LTV consistency, positive revenue, unique grain, monotonic running total"
        ),
    )

    # ─── 5. Documentation generation ─────────────────────────────────────────

    dbt_docs = BashOperator(
        task_id="dbt_docs_generate",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt docs generate --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        doc_md="Generates `catalog.json` + `manifest.json`. Browse via `dbt docs serve` locally.",
    )

    # ─── Dependencies ─────────────────────────────────────────────────────────
    #
    #   load_orders
    #       └── source_freshness
    #               ├── dbt_snapshot ─────────────────────────────┐
    #               └── dbt_run_staging                           │
    #                       └── dbt_run_intermediate              │
    #                               └── dbt_run_marts ────────────┤
    #                                                             ▼
    #                                                         dbt_test
    #                                                             └── dbt_docs

    load_orders >> source_freshness
    source_freshness >> [dbt_snapshot, dbt_run_staging]
    dbt_run_staging >> dbt_run_intermediate >> dbt_run_marts
    [dbt_snapshot, dbt_run_marts] >> dbt_test
    dbt_test >> dbt_docs
