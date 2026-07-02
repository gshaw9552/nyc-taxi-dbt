SELECT
    location_id,
    zone_name,
    borough,
    service_zone
FROM {{ ref('stg_taxi_zones') }}