{#
    apply_incremental_watermark(model_key=none, watermark_column=none, late_arrival_days=none)

    Generates the WHERE clause for a watermark-based incremental model, reading
    its tuning from the `incremental_configs` var in dbt_project.yml — same
    pattern as generate_staging_select(), same reasoning: var() is reliable,
    version-independent, and keeps the tuning knobs in one auditable place
    instead of a magic number buried inside a specific model's SQL.

    Returns an empty string on the first run (when is_incremental() is false),
    so it is always safe to call unconditionally — no need to wrap it in your
    own {% if is_incremental() %} block in the model.

    ─────────────────────────────────────────────────────────────────────────
    CONTRACT — the incremental_configs var this macro expects in dbt_project.yml:
    ─────────────────────────────────────────────────────────────────────────

    vars:
      incremental_configs:
        fct_trips_daily:
          watermark_column: trip_date     # column tracked as the high-water mark
          late_arrival_days: 3            # how far back to reprocess each run

    ─────────────────────────────────────────────────────────────────────────
    USAGE — in an incremental model, unconditionally, near the bottom:
    ─────────────────────────────────────────────────────────────────────────

    SELECT ...
    FROM {{ ref('some_upstream_model') }}
    {{ apply_incremental_watermark() }}
    GROUP BY ...

    Optional overrides, if you don't want to add a var entry for a one-off model:
        {{ apply_incremental_watermark(watermark_column='trip_date', late_arrival_days=5) }}

    ─────────────────────────────────────────────────────────────────────────
    WHY "late arrival days" AND NOT "no full refresh, ever":
    ─────────────────────────────────────────────────────────────────────────
    This macro eliminates full refresh due to FRAGILE incremental logic — the
    actual problem in the original project. It does not, and cannot, eliminate
    every legitimate reason for a full refresh: a genuine schema change to an
    incremental Delta table, or a backfill of data OLDER than the current max
    watermark (exactly what happened when March data was loaded after April
    was already the max — that is a real limitation of ANY forward-only
    watermark strategy, not something this macro papers over. See
    docs/backfill_playbook.md for the correct way to handle that case without
    a blind full refresh.)
#}

{% macro apply_incremental_watermark(model_key=none, watermark_column=none, late_arrival_days=none) %}

{%- if not is_incremental() -%}
    {# First run / full-refresh: no filter, process everything. #}
{%- else -%}

    {%- set key = model_key or this.name -%}
    {%- set all_configs = var('incremental_configs', {}) -%}
    {%- set cfg = all_configs.get(key, {}) -%}

    {%- set resolved_column = watermark_column or cfg.get('watermark_column') -%}
    {%- set resolved_days   = late_arrival_days if late_arrival_days is not none else cfg.get('late_arrival_days', 0) -%}

    {%- if not resolved_column -%}
        {{ exceptions.raise_compiler_error(
            "apply_incremental_watermark: no watermark_column configured for '" ~ key ~
            "'. Add an entry under vars.incremental_configs in dbt_project.yml, " ~
            "or pass watermark_column= explicitly to this macro call."
        ) }}
    {%- endif -%}

WHERE {{ resolved_column }} >= (
    SELECT DATE_ADD(MAX({{ resolved_column }}), -{{ resolved_days }})
    FROM {{ this }}
)

{%- endif -%}

{% endmacro %}