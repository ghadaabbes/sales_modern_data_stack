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
