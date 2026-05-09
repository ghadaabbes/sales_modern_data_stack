{{
  config(
    materialized='stream_merge',
    unique_key='order_id',
    stream_name='DWH.RAW.ORDERS_STREAM',
    tags=['staging', 'cdc']
  )
}}

/*
  CDC model driven by the Snowflake Stream on RAW.ORDERS.

  First run  : full load via CREATE TABLE AS SELECT (this SQL).
  Next runs  : the stream_merge materialization reads ORDERS_STREAM
               and applies a MERGE — no full table rebuild.

  METADATA$ACTION values handled by the materialization:
    INSERT  (METADATA$ISUPDATE = FALSE) → new row
    INSERT  (METADATA$ISUPDATE = TRUE)  → update (insert-half of delete+insert pair)
    DELETE  (METADATA$ISUPDATE = FALSE) → hard delete propagated to target
*/

SELECT
  order_id,
  customer_id,
  order_date,
  amount,
  status,
  country
FROM {{ source('raw', 'ORDERS') }}
WHERE order_id IS NOT NULL
