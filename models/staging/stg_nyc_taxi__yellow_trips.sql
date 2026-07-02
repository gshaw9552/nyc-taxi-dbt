WITH source AS (
    SELECT * FROM {{ source('raw', 'yellow_trips_raw') }}
),

cleaned AS (
    SELECT
        -- Rename columns to consistent snake_case
        VendorID                                    AS vendor_id,
        tpep_pickup_datetime                        AS pickup_at,
        tpep_dropoff_datetime                       AS dropoff_at,
        passenger_count,
        trip_distance,
        PULocationID                                AS pickup_location_id,
        DOLocationID                                AS dropoff_location_id,
        payment_type,
        fare_amount,
        tip_amount,
        tolls_amount,
        total_amount,

        -- Derived columns
        CAST(tpep_pickup_datetime AS DATE)          AS trip_date,
        HOUR(tpep_pickup_datetime)                  AS pickup_hour,
        DAYOFWEEK(tpep_pickup_datetime)             AS day_of_week

    FROM source

    -- Remove clearly invalid rows
    WHERE tpep_pickup_datetime IS NOT NULL
      AND tpep_dropoff_datetime IS NOT NULL
      AND tpep_pickup_datetime < tpep_dropoff_datetime
      AND trip_distance > 0
      AND total_amount > 0
)

SELECT * FROM cleaned