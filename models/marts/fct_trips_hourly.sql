SELECT
    trip_date,
    pickup_hour,
    pickup_borough,

    COUNT(*)                        AS total_trips,
    AVG(trip_duration_minutes)      AS avg_duration_min,
    SUM(total_amount)               AS total_revenue_usd

FROM {{ ref('int_trips__enriched') }}

GROUP BY
    trip_date,
    pickup_hour,
    pickup_borough