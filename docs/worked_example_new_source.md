# Worked Example — Adding a New Source With the Generator

This shows the actual, complete diff required to onboard a new source table
— NYC Green Taxi trips — using the generator. This is the concrete proof of
the "1 table or 100 tables, edit YAML only" requirement.

## Before (the old way, per the original repo)

Adding green taxi data required:
1. A new `taxi_zone_lookup`-style entry in `_sources.yml` (unavoidable, still true)
2. A brand new ~30-line hand-written `stg_nyc_taxi__green_trips.sql` file,
   re-deriving every rename/filter/derived-column decision from scratch
3. Manually updating `int_trips__enriched.sql` to union or join the new source
4. Manually re-declaring tests in `_staging.yml` for the new model

Steps 2 was the bulk of the actual work and the bulk of the risk — every
new source meant re-writing filter logic by hand, with no guarantee of
consistency with how yellow trips were filtered.

## After (with the generator)

### 1. Add the source + meta.staging config to `_sources.yml` — YAML only

```yaml
      - name: green_trips_raw
        description: "Raw green taxi (boro taxi) trip records."
        config:
          loaded_at_field: lpep_pickup_datetime
          freshness:
            warn_after: {count: 25, period: hour}
            error_after: {count: 49, period: hour}

        meta:
          staging:
            rename:
              VendorID: vendor_id
              lpep_pickup_datetime: pickup_at
              lpep_dropoff_datetime: dropoff_at
              PULocationID: pickup_location_id
              DOLocationID: dropoff_location_id
            passthrough:
              - passenger_count
              - trip_distance
              - payment_type
              - fare_amount
              - tip_amount
              - tolls_amount
              - total_amount
            derived_columns:
              trip_date: "CAST(lpep_pickup_datetime AS DATE)"
              pickup_hour: "HOUR(lpep_pickup_datetime)"
              day_of_week: "DAYOFWEEK(lpep_pickup_datetime)"
            filters:
              - "lpep_pickup_datetime IS NOT NULL"
              - "lpep_dropoff_datetime IS NOT NULL"
              - "lpep_pickup_datetime < lpep_dropoff_datetime"
              - "trip_distance > 0"
              - "total_amount > 0"

        columns:
          - name: lpep_pickup_datetime
            description: "Trip pickup timestamp (green taxi field name differs from yellow)"
          - name: lpep_dropoff_datetime
            description: "Trip dropoff timestamp"
```

Notice: the ONLY thing different from yellow taxi's config is the source
column names (`lpep_*` instead of `tpep_*`, which is a real, documented
naming difference between NYC's yellow and green taxi datasets) and dropping
the `2020-01-01` lower-bound filter that was specific to a data-quality issue
found in the yellow dataset. Everything else — the shape of the config
itself — is identical in structure.

### 2. Add one boilerplate model file — 1 line, not 30

`models/staging/stg_nyc_taxi__green_trips.sql`:
```sql
{{ generate_staging_select('raw', 'green_trips_raw') }}
```

### 3. Run it

```bash
dbt run --select stg_nyc_taxi__green_trips
dbt test --select stg_nyc_taxi__green_trips
```

## What Did NOT Need to Change

- `macros/generators/generate_staging_select.sql` — zero changes
- `dbt_project.yml` — zero changes
- Every other existing model — zero changes
- No new Python, no new test framework, no new anything except one YAML
  block and one boilerplate file

## What Still Needs Human Judgment (the honest limits)

- **Intermediate/mart integration is not automatic.** Deciding whether green
  trips should union into `int_trips__enriched` or get their own parallel
  intermediate model is a real business/data-modeling decision, not
  something a generator should silently decide for you. That said, if
  green and yellow share an identical grain and column set after staging
  (which they do here), a `union_relations()` pattern from `dbt_utils` is
  the next natural step — worth doing deliberately, not automatically.
- **Column-specific test values still need real knowledge of the new data**
  (e.g., green taxi's own `payment_type` code list, if it differs) — the
  generator handles the SELECT shape, not domain knowledge about valid values.
- **Genuinely bespoke sources still need a hand-written model.** That's the
  escape hatch documented in the generator macro itself — not a framework
  failure, a deliberate boundary.
