{{ config(
    materialized='incremental',
    unique_key=['trip_date', 'pickup_borough'],
    incremental_strategy='merge'
) }}

SELECT
    trip_date,
    pickup_borough,

    COUNT(*)                                        AS total_trips,
    SUM(fare_amount)                                AS total_fare_usd,
    SUM(tip_amount)                                 AS total_tips_usd,
    SUM(total_amount)                               AS total_revenue_usd,
    AVG(trip_distance)                              AS avg_trip_distance_miles,
    AVG(trip_duration_minutes)                      AS avg_trip_duration_min,
    AVG(CASE WHEN payment_type = 1
             THEN tip_pct END)                      AS avg_tip_pct_credit_card,
    SUM(CASE WHEN payment_type = 1
             THEN 1 ELSE 0 END)                     AS credit_card_trips,
    SUM(CASE WHEN payment_type = 2
             THEN 1 ELSE 0 END)                     AS cash_trips,

    {{ audit_columns() }}

FROM {{ ref('int_trips__enriched') }}

{% if is_incremental() %}
WHERE trip_date >= (
    SELECT DATE_ADD(MAX(trip_date), -3)
    FROM {{ this }}
)
{% endif %}

GROUP BY
    trip_date,
    pickup_borough