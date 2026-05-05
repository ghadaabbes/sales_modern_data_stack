#!/bin/bash
set -e

airflow db migrate

airflow users create \
  --username admin \
  --password admin \
  --firstname admin \
  --lastname admin \
  --role Admin \
  --email admin@example.com || true

airflow webserver &
airflow scheduler
