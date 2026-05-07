import logging
from datetime import datetime, timedelta

from airflow import DAG
from airflow.models import Variable
from airflow.operators.bash import BashOperator
from airflow.utils.trigger_rule import TriggerRule

DBT_PROJECT_DIR = "/opt/airflow/dbt_project"
SCRIPTS_DIR = "/opt/airflow/scripts"

# Cible dbt — surcharger via Airflow Variable "dbt_target" pour passer en prod
DBT_TARGET = Variable.get("dbt_target", default_var="dev")

# Credentials Snowflake injectés depuis Airflow Variables (jamais en dur dans le code)
DBT_ENV = {
    "DBT_SNOWFLAKE_PASSWORD":  Variable.get("snowflake_password",  default_var=""),
    "DBT_SNOWFLAKE_ACCOUNT":   Variable.get("snowflake_account",   default_var="GOERPYE-DR90600"),
    "DBT_SNOWFLAKE_USER":      Variable.get("snowflake_user",      default_var="GHADAAB"),
    "DBT_SNOWFLAKE_ROLE":      Variable.get("snowflake_role",      default_var="ACCOUNTADMIN"),
    "DBT_SNOWFLAKE_DATABASE":  Variable.get("snowflake_database",  default_var="DWH"),
    "DBT_SNOWFLAKE_WAREHOUSE": Variable.get("snowflake_warehouse", default_var="TRANSFORM_WH"),
}


def on_failure_callback(context: dict) -> None:
    """Log structuré en cas d'échec — extensible vers Slack / PagerDuty."""
    ti = context["task_instance"]
    logging.error(
        "[%s] Task '%s' échouée | run_id=%s | log: %s",
        ti.dag_id,
        ti.task_id,
        context["run_id"],
        ti.log_url,
    )
    # Pour notifier Slack, décommenter et configurer SlackWebhookOperator ici


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
    description="Pipeline ELT quotidien : RAW → staging → intermediate → marts + snapshot + tests + docs",
    default_args=default_args,
    start_date=datetime(2025, 1, 1),
    schedule="@daily",
    catchup=False,
    tags=["snowflake", "dbt", "data-engineering"],
    doc_md="""
## snowflake_dbt_pipeline

Pipeline ELT complet — s'exécute toutes les nuits à minuit.

### Flux d'exécution

```
load_orders_to_raw
    └── dbt_source_freshness
            ├── dbt_snapshot          ← SCD Type 2 en parallèle
            └── dbt_run_staging
                    └── dbt_run_intermediate
                            └── dbt_run_marts
                                    └── dbt_test  ← converge snapshot + marts
                                            └── dbt_docs_generate
```

### Variables Airflow à configurer
| Variable | Description |
|----------|-------------|
| `dbt_target` | Cible dbt : `dev` (défaut) ou `prod` |
| `snowflake_password` | Mot de passe Snowflake |
| `snowflake_account` | Identifiant du compte Snowflake |
| `snowflake_role` | Role Snowflake (`ACCOUNTADMIN` en dev) |
    """,
) as dag:

    # ─── 1. Chargement CSV → RAW ──────────────────────────────────────────────

    load_orders = BashOperator(
        task_id="load_orders_to_raw",
        bash_command=f"python {SCRIPTS_DIR}/load_orders_to_raw.py",
        env=DBT_ENV,
        execution_timeout=timedelta(minutes=15),
        doc_md="Charge `orders.csv` dans `DWH.RAW.ORDERS` via le script Python.",
    )

    # ─── 2. Fraîcheur source ──────────────────────────────────────────────────

    source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt source freshness --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        doc_md=(
            "Vérifie que `RAW.ORDERS` contient des données récentes.\n"
            "- Warning si > 24h\n"
            "- Erreur si > 48h"
        ),
    )

    # ─── 3a. Snapshot SCD Type 2 (parallèle avec staging) ────────────────────

    dbt_snapshot = BashOperator(
        task_id="dbt_snapshot",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt snapshot --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        doc_md=(
            "Exécute `orders_snapshot` (SCD Type 2).\n"
            "Capture chaque changement de `status` ou `amount` dans `SNAPSHOTS`."
        ),
    )

    # ─── 3b. Transformations par couche ──────────────────────────────────────

    dbt_run_staging = BashOperator(
        task_id="dbt_run_staging",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt run --select staging --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        doc_md="Construit `stg_orders` (view) dans le schéma STAGING.",
    )

    dbt_run_intermediate = BashOperator(
        task_id="dbt_run_intermediate",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt run --select intermediate --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        doc_md=(
            "Construit `int_orders_enriched` — dimensions temporelles "
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
            "Construit en parallèle dans Snowflake :\n"
            "- `fact_sales` — table de faits centrale\n"
            "- `agg_customers` — LTV, segmentation RFM\n"
            "- `sales_daily_kpi` — KPIs journaliers + window functions"
        ),
    )

    # ─── 4. Tests qualité (converge snapshot + marts) ─────────────────────────

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt test --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        trigger_rule=TriggerRule.ALL_SUCCESS,
        doc_md=(
            "Lance tous les tests :\n"
            "- Tests génériques : `not_null`, `unique`, `accepted_values`, `dbt_expectations`\n"
            "- Tests singuliers : cohérence LTV, revenue positif, grain unique, running total monotone"
        ),
    )

    # ─── 5. Génération documentation ─────────────────────────────────────────

    dbt_docs = BashOperator(
        task_id="dbt_docs_generate",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt docs generate --target {DBT_TARGET}"
        ),
        env=DBT_ENV,
        doc_md="Génère `catalog.json` + `manifest.json`. Consulter via `dbt docs serve` en local.",
    )

    # ─── Dépendances ──────────────────────────────────────────────────────────
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
