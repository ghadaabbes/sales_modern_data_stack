# ── Import existing resources ──────────────────────────────────────────────────
# These blocks allow Terraform to take over resources already in Snowflake.
# Safe to keep — if the resource is already in state, Terraform ignores the block.

import {
  to = snowflake_database.dwh
  id = "DWH"
}

import {
  to = snowflake_schema.raw
  id = "DWH.RAW"
}

import {
  to = snowflake_schema.staging
  id = "DWH.STAGING"
}

import {
  to = snowflake_schema.marts
  id = "DWH.MARTS"
}

import {
  to = snowflake_warehouse.transform_wh
  id = "TRANSFORM_WH"
}

# ── Database ───────────────────────────────────────────────────────────────────

resource "snowflake_database" "dwh" {
  name    = "DWH"
  comment = "Main data warehouse — contains all data layers."
}

# ── Schemas ────────────────────────────────────────────────────────────────────

resource "snowflake_schema" "raw" {
  name     = "RAW"
  database = snowflake_database.dwh.name
  comment  = "Raw data ingested as-is — never modified."
}

resource "snowflake_schema" "staging" {
  name     = "STAGING"
  database = snowflake_database.dwh.name
  comment  = "dbt cleaning views (stg_*, int_*)."
}

resource "snowflake_schema" "marts" {
  name     = "MARTS"
  database = snowflake_database.dwh.name
  comment  = "dbt analytical tables ready for BI (fact_*, agg_*, *_kpi)."
}

resource "snowflake_schema" "snapshots" {
  name     = "SNAPSHOTS"
  database = snowflake_database.dwh.name
  comment  = "SCD Type 2 snapshots managed by dbt (orders_snapshot)."
}

# ── Compute warehouse ──────────────────────────────────────────────────────────

resource "snowflake_warehouse" "transform_wh" {
  name           = "TRANSFORM_WH"
  warehouse_size = "XSMALL"
  auto_resume    = true
  auto_suspend   = 60
  comment        = "Dedicated dbt transformation warehouse. Auto-suspend after 60s."
}

# ── TRANSFORMER role (prod) ────────────────────────────────────────────────────
# Least-privilege role used in production (profiles.yml --target prod).
# Unlike ACCOUNTADMIN, it only has access to what dbt needs.

resource "snowflake_account_role" "transformer" {
  name    = "TRANSFORMER"
  comment = "dbt transformation role — used in production only."
}

# Usage on warehouse
resource "snowflake_grant_privileges_to_account_role" "transformer_warehouse" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.transform_wh.name
  }
}

# Usage on database
resource "snowflake_grant_privileges_to_account_role" "transformer_database" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.dwh.name
  }
}

# RAW: read-only (dbt source)
resource "snowflake_grant_privileges_to_account_role" "transformer_schema_raw" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = "\"${snowflake_database.dwh.name}\".\"${snowflake_schema.raw.name}\""
  }
}

# STAGING: read + create views/tables (dbt builds stg_* and int_* here)
resource "snowflake_grant_privileges_to_account_role" "transformer_schema_staging" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]

  on_schema {
    schema_name = "\"${snowflake_database.dwh.name}\".\"${snowflake_schema.staging.name}\""
  }
}

# MARTS: read + create tables (dbt builds fact_*, agg_*, *_kpi here)
resource "snowflake_grant_privileges_to_account_role" "transformer_schema_marts" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]

  on_schema {
    schema_name = "\"${snowflake_database.dwh.name}\".\"${snowflake_schema.marts.name}\""
  }
}

# SNAPSHOTS: read + create tables (dbt snapshot writes here)
resource "snowflake_grant_privileges_to_account_role" "transformer_schema_snapshots" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["USAGE", "CREATE TABLE"]

  on_schema {
    schema_name = "\"${snowflake_database.dwh.name}\".\"${snowflake_schema.snapshots.name}\""
  }
}

# ── CDC Stream ────────────────────────────────────────────────────────────────
# Captures every INSERT, UPDATE and DELETE on RAW.ORDERS.
# dbt reads this stream via the custom stream_merge materialization to apply
# a real MERGE (not a full table rebuild) into STAGING.STG_ORDERS_CDC.

resource "snowflake_stream_on_table" "orders_stream" {
  name     = "ORDERS_STREAM"
  database = snowflake_database.dwh.name
  schema   = snowflake_schema.raw.name
  table    = "\"${snowflake_database.dwh.name}\".\"${snowflake_schema.raw.name}\".\"ORDERS\""

  append_only = false # capture updates and deletes, not just inserts
  comment     = "CDC stream on RAW.ORDERS — feeds STG_ORDERS_CDC via MERGE."
}

# Grant SELECT on the stream to the TRANSFORMER role (prod)
resource "snowflake_grant_privileges_to_account_role" "transformer_stream_orders" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["SELECT"]

  on_schema_object {
    object_type = "STREAM"
    object_name = "\"${snowflake_database.dwh.name}\".\"${snowflake_schema.raw.name}\".\"ORDERS_STREAM\""
  }
}

# ── Outputs ────────────────────────────────────────────────────────────────────

output "database_name" {
  description = "Snowflake database name."
  value       = snowflake_database.dwh.name
}

output "schemas" {
  description = "List of provisioned schemas."
  value = {
    raw       = snowflake_schema.raw.name
    staging   = snowflake_schema.staging.name
    marts     = snowflake_schema.marts.name
    snapshots = snowflake_schema.snapshots.name
  }
}

output "warehouse_name" {
  description = "dbt compute warehouse name."
  value       = snowflake_warehouse.transform_wh.name
}

output "transformer_role" {
  description = "Prod role to assign to transformation users."
  value       = snowflake_account_role.transformer.name
}
