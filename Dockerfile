FROM apache/airflow:2.8.1-python3.11
RUN pip install --no-cache-dir dbt-snowflake==1.9.1
