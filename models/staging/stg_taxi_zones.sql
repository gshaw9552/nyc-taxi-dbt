WITH source AS (
    SELECT * FROM {{ source('raw', 'taxi_zone_lookup') }}
),

renamed AS (
    SELECT
        LocationID      AS location_id,
        Borough         AS borough,
        Zone            AS zone_name,
        service_zone
    FROM source
)

SELECT * FROM renamed