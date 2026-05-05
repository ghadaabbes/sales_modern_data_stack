from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime

DBT_PROJECT_DIR = "/opt/airflow/dbt_project"
SCRIPTS_DIR     = "/opt/airflow/dbt_project/../scripts"

with DAG(
    dag_id="snowflake_dbt_pipeline",
    start_date=datetime(2025, 1, 1),
    schedule_interval="@daily",
    catchup=False,
    tags=["snowflake", "dbt", "data-engineering"],
) as dag:

    load_orders = BashOperator(
        task_id="load_orders_to_raw",
        bash_command=f"python {SCRIPTS_DIR}/load_orders_to_raw.py",
    )

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=f"cd {DBT_PROJECT_DIR} && dbt run",
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"cd {DBT_PROJECT_DIR} && dbt test",
    )

    load_orders >> dbt_run >> dbt_test