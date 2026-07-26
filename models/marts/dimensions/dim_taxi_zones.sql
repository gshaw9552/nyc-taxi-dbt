SELECT
    location_id,
    zone_name,
    borough,
    service_zone,
    dbt_valid_from AS effective_from,
    dbt_updated_at AS last_changed_at

FROM {{ ref('zones_snapshot') }}

WHERE dbt_valid_to IS NULL