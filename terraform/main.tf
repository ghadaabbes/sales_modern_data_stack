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

resource "snowflake_database" "dwh" {
  name = "DWH"
}

resource "snowflake_schema" "raw" {
  name     = "RAW"
  database = snowflake_database.dwh.name
}

resource "snowflake_schema" "staging" {
  name     = "STAGING"
  database = snowflake_database.dwh.name
}

resource "snowflake_schema" "marts" {
  name     = "MARTS"
  database = snowflake_database.dwh.name
}

resource "snowflake_warehouse" "transform_wh" {
  name           = "TRANSFORM_WH"
  warehouse_size = "XSMALL"
  auto_resume    = true
  auto_suspend   = 60
}
