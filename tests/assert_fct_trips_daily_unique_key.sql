-- Checks that fct_trips_daily has no duplicate rows for the
-- same trip_date + pickup_borough combination.
-- Zero rows = test passes. Any rows = duplicate found, test fails.

SELECT
    trip_date,
    pickup_borough,
    COUNT(*) AS row_count
FROM {{ ref('fct_trips_daily') }}
GROUP BY
    trip_date,
    pickup_borough
HAVING COUNT(*) > 1