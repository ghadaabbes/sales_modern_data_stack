# ── Import des ressources existantes ──────────────────────────────────────────
# Ces blocs import permettent à Terraform de reprendre la gestion de ressources
# créées manuellement ou lors d'un premier run. À ne conserver que si l'état
# local est vide (premier terraform apply après un make clean).

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

# ── Base de données ────────────────────────────────────────────────────────────

resource "snowflake_database" "dwh" {
  name    = "DWH"
  comment = "Data warehouse principal — contient toutes les couches de données."
}

# ── Schémas ───────────────────────────────────────────────────────────────────

resource "snowflake_schema" "raw" {
  name     = "RAW"
  database = snowflake_database.dwh.name
  comment  = "Données brutes ingérées telles quelles — jamais modifiées."
}

resource "snowflake_schema" "staging" {
  name     = "STAGING"
  database = snowflake_database.dwh.name
  comment  = "Vues de nettoyage dbt (stg_*, int_*)."
}

resource "snowflake_schema" "marts" {
  name     = "MARTS"
  database = snowflake_database.dwh.name
  comment  = "Tables analytiques dbt prêtes pour la BI (fact_*, agg_*, *_kpi)."
}

resource "snowflake_schema" "snapshots" {
  name     = "SNAPSHOTS"
  database = snowflake_database.dwh.name
  comment  = "Snapshots SCD Type 2 gérés par dbt (orders_snapshot)."
}

# ── Warehouse de compute ───────────────────────────────────────────────────────

resource "snowflake_warehouse" "transform_wh" {
  name           = "TRANSFORM_WH"
  warehouse_size = "XSMALL"
  auto_resume    = true
  auto_suspend   = 60
  comment        = "Warehouse dédié aux transformations dbt. Auto-suspend après 60s."
}

# ── Role TRANSFORMER (prod) ────────────────────────────────────────────────────
# Role à privilèges réduits utilisé en production (profiles.yml --target prod).
# Contrairement à ACCOUNTADMIN, il n'a accès qu'à ce qui est nécessaire pour dbt.

resource "snowflake_role" "transformer" {
  name    = "TRANSFORMER"
  comment = "Role de transformation dbt — utilisé en production uniquement."
}

# Usage sur le warehouse
resource "snowflake_grant_privileges_to_role" "transformer_warehouse" {
  role_name  = snowflake_role.transformer.name
  privileges = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.transform_wh.name
  }
}

# Usage sur la database
resource "snowflake_grant_privileges_to_role" "transformer_database" {
  role_name  = snowflake_role.transformer.name
  privileges = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.dwh.name
  }
}

# RAW : lecture seule (SELECT) — source dbt
resource "snowflake_grant_privileges_to_role" "transformer_schema_raw" {
  role_name  = snowflake_role.transformer.name
  privileges = ["USAGE"]

  on_schema {
    schema_name = "\"${snowflake_database.dwh.name}\".\"${snowflake_schema.raw.name}\""
  }
}

resource "snowflake_grant_privileges_to_role" "transformer_tables_raw" {
  role_name  = snowflake_role.transformer.name
  privileges = ["SELECT"]

  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${snowflake_database.dwh.name}\".\"${snowflake_schema.raw.name}\""
    }
  }
}

# STAGING : lecture + création de vues (dbt crée les views stg_* et int_*)
resource "snowflake_grant_privileges_to_role" "transformer_schema_staging" {
  role_name  = snowflake_role.transformer.name
  privileges = ["USAGE", "CREATE TABLE", "CREATE VIEW"]

  on_schema {
    schema_name = "\"${snowflake_database.dwh.name}\".\"${snowflake_schema.staging.name}\""
  }
}

# MARTS : lecture + création de tables (dbt crée fact_*, agg_*, *_kpi)
resource "snowflake_grant_privileges_to_role" "transformer_schema_marts" {
  role_name  = snowflake_role.transformer.name
  privileges = ["USAGE", "CREATE TABLE", "CREATE VIEW"]

  on_schema {
    schema_name = "\"${snowflake_database.dwh.name}\".\"${snowflake_schema.marts.name}\""
  }
}

# SNAPSHOTS : lecture + création de tables (dbt snapshot écrit ici)
resource "snowflake_grant_privileges_to_role" "transformer_schema_snapshots" {
  role_name  = snowflake_role.transformer.name
  privileges = ["USAGE", "CREATE TABLE"]

  on_schema {
    schema_name = "\"${snowflake_database.dwh.name}\".\"${snowflake_schema.snapshots.name}\""
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "database_name" {
  description = "Nom de la database Snowflake."
  value       = snowflake_database.dwh.name
}

output "schemas" {
  description = "Liste des schémas provisionnés."
  value = {
    raw       = snowflake_schema.raw.name
    staging   = snowflake_schema.staging.name
    marts     = snowflake_schema.marts.name
    snapshots = snowflake_schema.snapshots.name
  }
}

output "warehouse_name" {
  description = "Nom du warehouse de compute dbt."
  value       = snowflake_warehouse.transform_wh.name
}

output "transformer_role" {
  description = "Role prod à assigner aux utilisateurs de transformation."
  value       = snowflake_role.transformer.name
}
