{#
    SCD Type 2 snapshot for taxi zones.

    Every time this runs and a zone's name, borough, or service_zone changes,
    dbt automatically:
      - closes out the old row (sets dbt_valid_to = now)
      - inserts a new row (dbt_valid_from = now, dbt_valid_to = null)

    This means the FULL HISTORY of every zone's attributes over time lives
    in this table permanently — nothing is ever overwritten or lost. Query
    it directly for "what was zone X classified as on date Y" style analysis.

    For "what is the zone RIGHT NOW" (the common case, used by marts), see
    models/marts/dimensions/dim_taxi_zones.sql, which reads only the current
    row (dbt_valid_to IS NULL) from this snapshot.

    check_cols lists exactly which columns trigger a new history row when
    changed. location_id is NOT in this list — it's the unique_key, and a
    change in location_id would mean a different zone entirely, not a
    changed attribute of the same zone.
#}

{% snapshot zones_snapshot %}

{{
    config(
      unique_key='location_id',
      strategy='check',
      check_cols=['zone_name', 'borough', 'service_zone'],
    )
}}

SELECT
    LocationID   AS location_id,
    Borough      AS borough,
    Zone         AS zone_name,
    service_zone

FROM {{ source('raw', 'taxi_zone_lookup') }}

{% endsnapshot %}