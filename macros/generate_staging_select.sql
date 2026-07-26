{#
    generate_staging_select(table_name)

    Generates a complete staging SELECT statement from configuration declared
    in the `staging_configs` var in dbt_project.yml. This replaces hand-writing
    a rename/filter/derive SQL block for every new source table.

    Why vars instead of reading sources.yml directly: var() is a basic, always
    available Jinja function with no dependency on manifest/graph parse timing
    or dbt-version-specific graph object structure. This is the reliable,
    boring choice on purpose.

    ─────────────────────────────────────────────────────────────────────────
    CONTRACT — the staging_configs var this macro expects in dbt_project.yml:
    ─────────────────────────────────────────────────────────────────────────

    vars:
      staging_configs:
        some_raw_table:                # must match the key you pass in below
          source_name: raw             # the source() block name in sources.yml
          rename:                      # raw_column: clean_column
            RawColumnName: clean_name
          passthrough:                 # columns kept as-is, no rename
            - already_clean_column
          derived_columns:              # clean_alias: raw SQL expression
            trip_date: "CAST(pickup_ts AS DATE)"
          filters:                      # list of SQL boolean conditions,
            - "pickup_ts IS NOT NULL"   # ANDed together in the WHERE clause
            - "trip_distance > 0"

    rename / passthrough / derived_columns / filters are all optional —
    an empty/omitted key just contributes nothing. source_name is required.

    ─────────────────────────────────────────────────────────────────────────
    IMPORTANT LIMITATION — read before assuming "zero SQL files, ever":
    ─────────────────────────────────────────────────────────────────────────
    dbt Core discovers models by scanning .sql files at parse time. There is
    no supported way to make N models materialize from a single file with
    zero per-model files. What this macro DOES eliminate is per-model SQL
    LOGIC — every staging model file becomes a one-line call to this macro.
    Adding source table #101 means adding a block to the staging_configs var
    and one boilerplate one-line .sql file — not writing or copy-pasting
    30 lines of SELECT logic.

    ESCAPE HATCH: if a source genuinely needs bespoke logic this macro can't
    express (window functions, complex CASE trees, multi-table unions), just
    write a normal hand-authored .sql model for that one source instead of
    calling this macro. Nothing else in the framework needs to change — the
    generator is an option per model, not a requirement.
#}

{% macro generate_staging_select(table_name) %}

{%- set all_configs = var('staging_configs', {}) -%}

{%- if table_name not in all_configs -%}
    {{ exceptions.raise_compiler_error(
        "generate_staging_select: no entry for '" ~ table_name ~ "' found in " ~
        "the staging_configs var. Add a block for it under vars.staging_configs " ~
        "in dbt_project.yml."
    ) }}
{%- endif -%}

{%- set cfg = all_configs[table_name] -%}
{%- set source_name = cfg.get('source_name') -%}

{%- if not source_name -%}
    {{ exceptions.raise_compiler_error(
        "generate_staging_select: staging_configs['" ~ table_name ~ "'] is " ~
        "missing a required 'source_name' key."
    ) }}
{%- endif -%}

{%- set rename_map       = cfg.get('rename', {}) -%}
{%- set passthrough_cols = cfg.get('passthrough', []) -%}
{%- set derived_columns  = cfg.get('derived_columns', {}) -%}
{%- set filters          = cfg.get('filters', []) -%}

{%- if (rename_map | length) == 0
    and (passthrough_cols | length) == 0
    and (derived_columns | length) == 0 -%}
    {{ exceptions.raise_compiler_error(
        "generate_staging_select: staging_configs['" ~ table_name ~ "'] has no " ~
        "rename, passthrough, or derived_columns configured, so there is " ~
        "nothing to select."
    ) }}
{%- endif -%}

{%- set select_lines = [] -%}
{%- for raw_col, clean_col in rename_map.items() -%}
    {%- do select_lines.append(raw_col ~ ' as ' ~ clean_col) -%}
{%- endfor -%}
{%- for col in passthrough_cols -%}
    {%- do select_lines.append(col) -%}
{%- endfor -%}
{%- for alias, expr in derived_columns.items() -%}
    {%- do select_lines.append(expr ~ ' as ' ~ alias) -%}
{%- endfor -%}

with source as (
    select * from {{ source(source_name, table_name) }}
),

renamed as (
    select
        {{ select_lines | join(',\n        ') }}
    from source
    {%- if (filters | length) > 0 %}
    where {{ filters | join('\n      and ') }}
    {%- endif %}
)

select * from renamed

{% endmacro %}