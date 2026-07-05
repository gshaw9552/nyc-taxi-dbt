{% macro audit_columns() %}
    CURRENT_TIMESTAMP()         AS _dbt_loaded_at,
    '{{ invocation_id }}'       AS _dbt_run_id,
    '{{ this.name }}'           AS _dbt_model_name
{% endmacro %}