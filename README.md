# nyc-taxi-dbt

A production-quality dbt pipeline on Databricks Free Edition using NYC Taxi
Trip data. Structured as a reusable template for warehouse-only data engineering.

## What This Project Does

Transforms raw NYC Taxi Trip records through three quality layers:

- **Staging**: Cleans, renames, and validates raw source data (views, zero storage cost)
- **Intermediate**: Enriches trips with zone names and calculated metrics (ephemeral CTEs, zero storage cost)
- **Marts**: Daily and hourly aggregations ready for reporting (incremental Delta tables)

## Prerequisites

- Python 3.8+
- Databricks workspace (Free Edition works)
- SQL Warehouse created in Databricks (2X-Small, auto-stop 10 min recommended)
- NYC Taxi raw data loaded into `nyc_taxi.raw.yellow_trips_raw`
- Taxi zone lookup loaded into `nyc_taxi.raw.taxi_zone_lookup`

See `docs/architecture.md` for the full pipeline diagram and design decisions.

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/YOURUSERNAME/nyc-taxi-dbt.git
cd nyc-taxi-dbt
```

### 2. Create a virtual environment

```bash
python3 -m venv dbt-env
source dbt-env/bin/activate
pip install dbt-databricks
```

### 3. Set environment variables

```bash
export DATABRICKS_HOST=your-workspace.azuredatabricks.net
export DATABRICKS_TOKEN=your-personal-access-token
export DATABRICKS_HTTP_PATH=/sql/1.0/warehouses/your-warehouse-id
```

Add these three lines to `~/.zshrc` or `~/.bashrc` so they persist across terminal sessions.

### 4. Configure your dbt profile

Copy `docs/profiles_template.yml` to `~/.dbt/profiles.yml`.
The file uses `env_var()` so no credentials are hardcoded.

```bash
cp docs/profiles_template.yml ~/.dbt/profiles.yml
```

### 5. Install packages and verify connection

```bash
dbt deps
dbt debug
```

`dbt debug` should end with: `All checks passed!`

## Running the Pipeline

```bash
# Development run — writes to dev_staging and dev_marts schemas
dbt run

# Run models then immediately test them
dbt run && dbt test

# Production run — writes to prod_staging and prod_marts schemas
dbt run --target prod

# Rebuild all tables from scratch (use after schema changes)
dbt run --full-refresh

# Check whether source data is fresh
dbt source freshness

# Run tests only
dbt test

# Run a single model
dbt run --select fct_trips_daily

# Run a model and everything downstream of it
dbt run --select fct_trips_daily+
```

## Viewing Documentation and Lineage

```bash
dbt docs generate
dbt docs serve
```

Open http://localhost:8080 in your browser. Click any model to see its
description and columns. Click the graph icon (bottom right of any model page)
to view the full interactive lineage graph.

Press Ctrl+C in the terminal to stop the docs server when done.

## Project Structure

```
nyc_taxi_dbt/
├── dbt_project.yml                    # Master config: layer materializations and schemas
├── packages.yml                       # dbt-utils package dependency
├── README.md                          # This file
│
├── models/
│   ├── staging/                       # One model per source table
│   │   ├── _sources.yml               # Raw source declarations and freshness config
│   │   ├── _staging.yml               # Staging model descriptions and tests
│   │   ├── stg_nyc_taxi__yellow_trips.sql
│   │   └── stg_taxi_zones.sql
│   │
│   ├── intermediate/                  # Joins and enrichment (ephemeral)
│   │   ├── _intermediate.yml
│   │   └── int_trips__enriched.sql
│   │
│   └── marts/                         # Business-ready aggregations
│       ├── _marts.yml
│       ├── fct_trips_daily.sql        # Incremental daily aggregation
│       ├── fct_trips_hourly.sql       # Hourly aggregation
│       └── dim_taxi_zones.sql         # Zone reference dimension
│
├── macros/
│   ├── generate_schema_name.sql       # Dev/prod schema routing
│   └── audit_columns.sql             # Adds _dbt_loaded_at, _dbt_run_id tracking
│
├── tests/                             # Custom singular data quality tests
│   ├── assert_no_future_trips.sql
│   └── assert_fct_trips_daily_unique_key.sql
│
├── docs/
│   ├── architecture.md               # Pipeline diagram and design decisions
│   └── profiles_template.yml         # Template for ~/.dbt/profiles.yml
│
└── .github/
    └── workflows/
        └── dbt_daily_run.yml         # GitHub Actions daily scheduler
```

## Scheduling

Daily runs are automated via GitHub Actions (`.github/workflows/dbt_daily_run.yml`).

The workflow triggers at 6 AM UTC every day and:
1. Checks source freshness (non-blocking — pipeline continues even if stale)
2. Runs all dbt models against the prod target
3. Runs all dbt tests against the prod target

GitHub Actions free tier provides 2,000 minutes per month on private repos.
This pipeline uses approximately 100-150 minutes per month.

To trigger a manual run: GitHub repo → Actions tab → dbt Daily Run → Run workflow.

## Adapting This Template for a New Project

1. Update `models/staging/_sources.yml` with your new source tables in Databricks
2. Create new `stg_` models in `models/staging/` — one per source table
3. Update `models/intermediate/int_trips__enriched.sql` with your joins and business logic
4. Update or replace mart models with your aggregations
5. Update all YAML files with column descriptions and tests relevant to your data
6. Update `dbt_project.yml` project name if desired
7. Add new GitHub Secrets if using a different Databricks workspace

Estimated time to adapt for a new dataset with a similar structure: 4-8 hours.

## Cost Summary

| Component | Configuration | Cost |
|---|---|---|
| SQL Warehouse | 2X-Small, auto-stop 10 min | ~$0 on Free Edition |
| Staging storage | Views (no physical storage) | $0 |
| Intermediate storage | Ephemeral CTEs (no tables created) | $0 |
| Mart storage | Small incremental Delta tables | Minimal |
| Scheduling | GitHub Actions free tier | $0 |

## Key Design Decisions

- **No Spark clusters** — SQL Warehouse only for all transformations
- **No Python dbt models** — pure SQL throughout
- **No DLT** — not available on Free Edition, not needed for batch SQL
- **No Databricks Workflows** — GitHub Actions handles scheduling for free
- **Incremental strategy** — marts process only new rows on each daily run
- **Ephemeral intermediate** — zero storage cost for enrichment logic
- **Schema routing macro** — dev and prod schemas never collide