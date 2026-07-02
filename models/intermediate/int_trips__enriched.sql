WITH trips AS (
    SELECT * FROM {{ ref('stg_nyc_taxi__yellow_trips') }}
),

pickup_zones AS (
    SELECT * FROM {{ ref('stg_taxi_zones') }}
),

dropoff_zones AS (
    SELECT * FROM {{ ref('stg_taxi_zones') }}
),

enriched AS (
    SELECT
        -- Trip timing
        t.trip_date,
        t.pickup_at,
        t.dropoff_at,
        t.pickup_hour,
        t.day_of_week,

        -- Trip metrics
        t.trip_distance,
        t.passenger_count,
        t.fare_amount,
        t.tip_amount,
        t.tolls_amount,
        t.total_amount,
        t.payment_type,

        -- Calculated duration in minutes
        ROUND(
            (UNIX_TIMESTAMP(t.dropoff_at) - UNIX_TIMESTAMP(t.pickup_at)) / 60,
            2
        ) AS trip_duration_minutes,

        -- Tip percentage (credit card trips only)
        CASE
            WHEN t.payment_type = 1 AND t.fare_amount > 0
            THEN ROUND(t.tip_amount / t.fare_amount * 100, 2)
            ELSE NULL
        END AS tip_pct,

        -- Pickup location
        t.pickup_location_id,
        pu.zone_name    AS pickup_zone,
        pu.borough      AS pickup_borough,

        -- Dropoff location
        t.dropoff_location_id,
        dz.zone_name    AS dropoff_zone,
        dz.borough      AS dropoff_borough,

        -- Vendor
        t.vendor_id

    FROM trips t
    LEFT JOIN pickup_zones pu
        ON t.pickup_location_id = pu.location_id
    LEFT JOIN dropoff_zones dz
        ON t.dropoff_location_id = dz.location_id

    -- Filter out unreasonable trips
    WHERE ROUND(
              (UNIX_TIMESTAMP(t.dropoff_at) - UNIX_TIMESTAMP(t.pickup_at)) / 60,
              2
          ) BETWEEN 1 AND 300
      AND t.trip_distance <= 100
)

SELECT * FROM enriched