# Validating the Generator Against the Original Models

Before trusting this generator for a new, unfamiliar source, prove to yourself
that it reproduces the two EXISTING models byte-for-byte equivalent in output
(not necessarily identical SQL text, but identical result set / column list).
Do this before deleting the original hand-written versions.

## Step 1 — Compile Both Versions Side-by-Side

Don't overwrite the original files yet. Instead:

1. Rename the new generator-based files temporarily:
   `stg_nyc_taxi__yellow_trips.sql` -> `stg_nyc_taxi__yellow_trips_v2.sql`
   (and update the macro call's model won't matter — dbt names models by
   filename regardless of content)

2. Run:
   ```bash
   dbt compile --select stg_nyc_taxi__yellow_trips stg_nyc_taxi__yellow_trips_v2
   ```

3. Open both compiled files and compare:
   ```bash
   diff target/compiled/<project>/models/staging/stg_nyc_taxi__yellow_trips.sql \
        target/compiled/<project>/models/staging/stg_nyc_taxi__yellow_trips_v2.sql
   ```

   You should see the SAME columns selected, the SAME filter logic, just
   possibly reordered (the generator emits rename -> passthrough -> derived,
   which may not match your original file's exact column order — that's fine,
   column ORDER in a SELECT never matters for correctness, only NAMES do).

## Step 2 — Run Both, Compare Row Counts and a Content Hash

```bash
dbt run --select stg_nyc_taxi__yellow_trips stg_nyc_taxi__yellow_trips_v2
```

Then in Databricks SQL Editor:

```sql
-- Row counts must match exactly
SELECT
    (SELECT COUNT(*) FROM nyc_taxi.dev_staging.stg_nyc_taxi__yellow_trips)    AS original_count,
    (SELECT COUNT(*) FROM nyc_taxi.dev_staging.stg_nyc_taxi__yellow_trips_v2) AS generated_count;

-- A full content diff — this should return ZERO rows if the two models
-- produce identical data (ignoring column order)
SELECT * FROM nyc_taxi.dev_staging.stg_nyc_taxi__yellow_trips
EXCEPT
SELECT * FROM nyc_taxi.dev_staging.stg_nyc_taxi__yellow_trips_v2;

SELECT * FROM nyc_taxi.dev_staging.stg_nyc_taxi__yellow_trips_v2
EXCEPT
SELECT * FROM nyc_taxi.dev_staging.stg_nyc_taxi__yellow_trips;
```

Both `EXCEPT` queries returning zero rows is the actual proof — row count
matching alone isn't sufficient (two models could have the same count but
different content).

## Step 3 — Once Proven Equivalent, Cut Over

1. Delete the original hand-written `stg_nyc_taxi__yellow_trips.sql`
2. Rename `stg_nyc_taxi__yellow_trips_v2.sql` -> `stg_nyc_taxi__yellow_trips.sql`
3. Run `dbt run --full-refresh --select stg_nyc_taxi__yellow_trips+` to rebuild
   everything downstream under the final model name
4. Run `dbt test` — all existing tests in `_staging.yml` should still pass
   unchanged, since the generator produces the same column names the tests
   already reference

Repeat the same process for `stg_taxi_zones`.

## Why This Matters Enough to Do Properly

The whole point of this generator is that you will trust it for sources you
have NEVER manually reviewed the SQL for — that's the entire value
proposition of "edit YAML only." That trust has to be earned once, on data
you already know intimately (yellow trips, taxi zones), before you extend it
to a source you don't yet have hand-verified intuition for.
