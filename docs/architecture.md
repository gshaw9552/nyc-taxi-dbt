# Data Architecture

## Pipeline Overview

```
NYC TLC Public Data (Parquet files)
              │
              ▼
  Manual Upload to Databricks Volume
  (nyc_taxi.raw.landing volume)
              │
              ▼
  COPY INTO Delta table
              │
              ├─────────────────────────────────────────┐
              ▼                                         ▼
nyc_taxi.raw.yellow_trips_raw            nyc_taxi.raw.taxi_zone_lookup
(Bronze: raw trip records)               (Bronze: static reference data)
              │                                         │
              ▼                                         ▼
  dbt staging layer (views — zero storage cost)
              │                                         │
              ▼                                         ▼
stg_nyc_taxi__yellow_trips               stg_taxi_zones
(cleaned, renamed, filtered)             (renamed, _rescued_data excluded)
              │                                         │
              └──────────────┬──────────────────────────┘
                             ▼
              dbt intermediate layer (ephemeral — zero storage cost)
                             │
                             ▼
                  int_trips__enriched
                  (trips joined to pickup and dropoff zones,
                   trip duration and tip percentage calculated,
                   outlier trips filtered)
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
   dbt marts layer (incremental Delta tables)
              │              │              │
              ▼              ▼              ▼
fct_trips_daily    fct_trips_hourly    dim_taxi_zones
(daily aggregation  (hourly aggregation  (zone reference
 by borough)         by borough)          dimension)
```

## Schema Layout

| Schema | Contains | Created by | Used by |
|---|---|---|---|
| `nyc_taxi.raw` | Raw ingested tables | Manual / COPY INTO | dbt sources |
| `dev_staging` | Staging views (dev) | dbt local runs | Development only |
| `dev_marts` | Mart tables (dev) | dbt local runs | Development only |
| `prod_staging` | Staging views (prod) | GitHub Actions | Production |
| `prod_marts` | Mart tables (prod) | GitHub Actions | BI tools / reporting |

The `generate_schema_name` macro controls this routing automatically.
The dev/prod separation means local development never overwrites production data.

## Materialization Decisions

| Layer | Materialization | Reason |
|---|---|---|
| Staging | `view` | Zero storage cost. Always reflects current raw data. |
| Intermediate | `ephemeral` | Compiled as CTEs inside mart SQL. No table created, no storage cost. |
| `dim_taxi_zones` | `table` | Small static reference table. Full rebuild is fast and simple. |
| `fct_trips_daily` | `incremental` (merge) | Large fact table. Only processes last 3 days on each run. |
| `fct_trips_hourly` | `table` | Moderate size. Acceptable to rebuild daily at current scale. |

## Incremental Strategy Detail

`fct_trips_daily` uses `incremental_strategy='merge'` on Databricks Delta Lake.

- **First run** (`--full-refresh`): processes all rows, creates the Delta table
- **Subsequent runs**: processes only rows where `trip_date >= MAX(trip_date) - 3 days`
- **Why 3 days**: TLC data sometimes backdates records; 3-day lookback handles late arrivals
- **Merge key**: `['trip_date', 'pickup_borough']` — existing rows are updated, new rows inserted
- **Result**: daily runs process ~300K rows instead of 3.6M regardless of total history size

## Raw Data Ingestion Pattern

```sql
-- Step 1: Create Delta table with timestampNtz support (required for NYC Taxi data)
CREATE TABLE IF NOT EXISTS nyc_taxi.raw.yellow_trips_raw
USING DELTA
TBLPROPERTIES (
    'delta.feature.timestampNtz' = 'supported',
    'delta.minReaderVersion' = '3',
    'delta.minWriterVersion' = '7'
);

-- Step 2: Load Parquet files from Volume into Delta table
COPY INTO nyc_taxi.raw.yellow_trips_raw
FROM '/Volumes/nyc_taxi/raw/landing/'
FILEFORMAT = PARQUET
COPY_OPTIONS ('mergeSchema' = 'true');
```

The `timestampNtz` TBLPROPERTIES are required because NYC Taxi Parquet files
store timestamps without timezone info. Without these properties, COPY INTO
fails with a Delta feature enablement error.

For small static reference files (taxi zone lookup), use CTAS with `read_files()`:

```sql
CREATE TABLE IF NOT EXISTS nyc_taxi.raw.taxi_zone_lookup
USING DELTA
AS
SELECT * FROM read_files(
    '/Volumes/nyc_taxi/raw/landing/taxi_zone_lookup.csv',
    format => 'csv',
    header => true,
    inferSchema => true
);
```

Note: `read_files()` adds a `_rescued_data` column automatically. This is a
Databricks safety net for malformed rows. It is excluded in `stg_taxi_zones`
by selecting only the four real columns explicitly.

## Data Quality

Tests are declared in YAML files alongside each model layer.

| Test type | Where declared | Examples |
|---|---|---|
| `not_null` | `_staging.yml`, `_marts.yml` | pickup_at, total_amount, trip_date |
| `unique` | `_staging.yml`, `_marts.yml` | location_id in dim_taxi_zones |
| `accepted_values` | `_staging.yml` | payment_type (0-6), borough names |
| Singular SQL tests | `tests/` folder | No future trips, no duplicate mart keys |

All tests run as part of the GitHub Actions daily workflow after `dbt run`.
Source freshness is checked before models run (non-blocking).

## Audit Trail

Every mart table includes three audit columns added via the `audit_columns` macro:

| Column | Content | Purpose |
|---|---|---|
| `_dbt_loaded_at` | Timestamp of the dbt run | Know when each row was last refreshed |
| `_dbt_run_id` | UUID of the specific dbt invocation | Trace a row back to a specific pipeline run |
| `_dbt_model_name` | Name of the dbt model that wrote the row | Useful when debugging multi-model pipelines |

## Design Constraints

This project is intentionally constrained to:

- **Databricks Free Edition** — no paid tier features assumed
- **SQL Warehouse only** — no Spark cluster-based design
- **Pure SQL dbt models** — no Python models (requires Spark, not SQL Warehouse)
- **No DLT** — Delta Live Tables not available on Free Edition
- **No Databricks Workflows** — GitHub Actions used for scheduling instead
- **Cost optimization as primary constraint** — every design decision evaluated against cost

## Expanding This Project

When ready to scale, these additions make sense in this order:

1. **Add more months of data** — COPY INTO handles this; incremental models handle the growth
2. **Add green taxi data** — new source declaration, new `stg_nyc_taxi__green_trips.sql`, update intermediate
3. **Add Elementary** — open-source dbt monitoring dashboard for run history
4. **Migrate to Databricks Workflows** — when Free Edition limits are outgrown
5. **Add row-level security** — Unity Catalog feature available on paid tiers
6. **Add more mart models** — payment analysis, driver performance, zone revenue ranking