-- Finds trips with a pickup date in the future.
-- Zero rows = test passes. Any rows = test fails.
-- This catches timestamp loading errors or timezone issues.

SELECT *
FROM {{ ref('stg_nyc_taxi__yellow_trips') }}
WHERE pickup_at > CURRENT_TIMESTAMP()