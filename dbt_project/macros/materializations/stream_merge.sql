/*
  Custom materialization: stream_merge
  =====================================
  Implements real CDC (Change Data Capture) using Snowflake Streams + MERGE.

  Required config:
    - unique_key   : primary key column (string)
    - stream_name  : fully qualified stream name (e.g. 'DWH.RAW.ORDERS_STREAM')

  How it works:
    First run  → CREATE TABLE from the model SQL (initial full load)
    Next runs  → MERGE stream changes into the target table:
                   INSERT  → new rows added to source
                   UPDATE  → METADATA$ISUPDATE = TRUE  (delete + insert pair)
                   DELETE  → rows removed from source

  Metadata columns added to target table:
    _cdc_action  : 'INITIAL_LOAD' | 'INSERT' | 'UPDATE' | 'DELETE'
    _loaded_at   : TIMESTAMP_NTZ of when the row was last processed
*/

{% materialization stream_merge, adapter='snowflake' %}

  {%- set unique_key  = config.require('unique_key') -%}
  {%- set stream_name = config.require('stream_name') -%}
  {%- set target      = this.incorporate(type='table') -%}

  {{ run_hooks(pre_hooks) }}

  {%- set target_exists = adapter.get_relation(
        database=target.database,
        schema=target.schema,
        identifier=target.identifier
  ) is not none -%}

  {% if not target_exists %}

    -- ── First run: full initial load from model SQL ──────────────────────────
    {% call statement('initial_load') %}
      CREATE TABLE {{ target }} AS
      SELECT
        src.*,
        'INITIAL_LOAD'::VARCHAR(20)  AS _cdc_action,
        CURRENT_TIMESTAMP()          AS _loaded_at
      FROM ({{ sql }}) AS src
    {% endcall %}

  {% else %}

    -- ── Incremental run: apply CDC changes from stream via MERGE ─────────────
    {%- set cols = adapter.get_columns_in_relation(target)
        | rejectattr('name', 'equalto', '_CDC_ACTION')
        | rejectattr('name', 'equalto', '_LOADED_AT')
        | list -%}

    {%- set update_cols = cols
        | rejectattr('name', 'equalto', unique_key | upper)
        | list -%}

    {% call statement('stream_merge') %}

      MERGE INTO {{ target }} AS tgt

      -- Stream rows: INSERT action covers both new inserts and the insert-half
      -- of an update pair (METADATA$ISUPDATE distinguishes them).
      USING (
        SELECT
          {% for col in cols %}
          {{ col.name }},
          {% endfor %}
          METADATA$ACTION    AS _stream_action,
          METADATA$ISUPDATE  AS _stream_is_update
        FROM {{ stream_name }}
        WHERE METADATA$ACTION IN ('INSERT', 'DELETE')
      ) AS src

      ON tgt.{{ unique_key }} = src.{{ unique_key }}

      -- DELETE: row removed from source table
      WHEN MATCHED
        AND src._stream_action   = 'DELETE'
        AND src._stream_is_update = FALSE
      THEN DELETE

      -- UPDATE: Snowflake streams emit a DELETE + INSERT pair for updates.
      -- We match on the INSERT half where METADATA$ISUPDATE = TRUE.
      WHEN MATCHED
        AND src._stream_action   = 'INSERT'
        AND src._stream_is_update = TRUE
      THEN UPDATE SET
        {% for col in update_cols %}
        tgt.{{ col.name }} = src.{{ col.name }},
        {% endfor %}
        tgt._cdc_action = 'UPDATE',
        tgt._loaded_at  = CURRENT_TIMESTAMP()

      -- INSERT: genuinely new row
      WHEN NOT MATCHED
        AND src._stream_action = 'INSERT'
      THEN INSERT (
        {% for col in cols %}{{ col.name }},{% endfor %}
        _cdc_action,
        _loaded_at
      )
      VALUES (
        {% for col in cols %}src.{{ col.name }},{% endfor %}
        'INSERT',
        CURRENT_TIMESTAMP()
      )

    {% endcall %}

  {% endif %}

  {{ run_hooks(post_hooks) }}
  {{ return({'relations': [target]}) }}

{% endmaterialization %}
