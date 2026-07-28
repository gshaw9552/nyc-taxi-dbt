# nyc-taxi-dbt

A production-quality dbt framework on Databricks Free Edition, built around the NYC Taxi dataset as a working example.

This repository has evolved from a single taxi analytics project into a reusable dbt template with:
- config-driven staging generation
- incremental watermark loading
- SCD Type 2 snapshots
- automated ingestion on Databricks
- GitHub-triggered Databricks execution
- backfill and validation playbooks
- a documented path for adding new sources

## What This Project Does

This project transforms raw NYC Taxi Trip records through a production-style warehouse pipeline:

- **Bronze / Raw**: Parquet files land in a Databricks Volume and are loaded into Delta with `COPY INTO`
- **Staging**: Source-specific configs generate clean, renamed, validated views
- **Intermediate**: Reusable enrichment logic combines trips with zone data and derived metrics
- **Marts**: Incremental fact tables, dimensions, and reporting-ready aggregations
- **Snapshots**: SCD Type 2 history is retained for slowly changing dimensions

The current implementation includes:
- Databricks SQL Warehouse
- dbt Core
- source freshness checks
- reusable macros
- incremental merge logic
- audit columns
- SCD framework
- automated ingestion
- Databricks Job trigger from GitHub
- validation and backfill docs

## Repository Features

### Generic staging generation
Staging models use a generator macro:
- `generate_staging_select()`
- configured through `vars.staging_configs` in `dbt_project.yml`

That means staging logic is centralised in YAML instead of repeated across many SQL files.

### Incremental loading
Incremental marts use:
- `apply_incremental_watermark()`
- configurable watermark columns
- configurable late-arrival windows
- merge strategy on Delta

This is designed for forward-moving data with a small reprocessing window.

### SCD support
The repository includes a working SCD Type 2 example for taxi zones:
- `snapshots/zones_snapshot.sql`
- `models/marts/dimensions/dim_taxi_zones.sql`

### Automated ingestion
The ingestion layer is separated from dbt:
- `ingestion/ingest_yellow_trips.sql`
- loaded via a Databricks Job task
- triggered by GitHub push through `.github/workflows/trigger_databricks_job.yml`

### Operational docs
The repo also includes:
- `docs/automated_ingestion_setup.md`
- `docs/backfill_playbook.md`
- `docs/scd_framework_guide.md`
- `docs/validation_notes.md`
- `docs/worked_example_new_source.md`

## Tech Stack

- **Databricks SQL Warehouse**
- **dbt Core**
- **Delta Lake**
- **GitHub Actions**
- **Databricks Jobs**
- **YAML-driven configuration**
- **dbt-utils**

## Project Structure

```text
nyc_taxi_dbt/
├── dbt_project.yml
├── packages.yml
├── package-lock.yml
├── README.md
│
├── ingestion/
│   └── ingest_yellow_trips.sql
│
├── macros/
│   ├── audit_columns.sql
│   ├── apply_incremental_watermark.sql
│   ├── generate_schema_name.sql
│   └── generate_staging_select.sql
│
├── models/
│   ├── staging/
│   │   ├── _sources.yml
│   │   ├── _staging.yml
│   │   ├── stg_nyc_taxi__yellow_trips.sql
│   │   └── stg_taxi_zones.sql
│   │
│   ├── intermediate/
│   │   ├── _intermediate.yml
│   │   └── int_trips__enriched.sql
│   │
│   └── marts/
│       ├── _marts.yml
│       ├── fct_trips_daily.sql
│       ├── fct_trips_hourly.sql
│       └── dimensions/
│           ├── _dimensions.yml
│           └── dim_taxi_zones.sql
│
├── snapshots/
│   └── zones_snapshot.sql
│
├── tests/
│   ├── assert_no_future_trips.sql
│   └── assert_fct_trips_daily_unique_key.sql
│
├── docs/
│   ├── architecture.md
│   ├── automated_ingestion_setup.md
│   ├── backfill_playbook.md
│   ├── profile_template.yml
│   ├── scd_framework_guide.md
│   ├── validation_notes.md
│   └── worked_example_new_source.md
│
└── .github/
    └── workflows/
        └── trigger_databricks_job.yml

## Architecture Overview

```text
NYC TLC public Parquet files
        ↓
Databricks Volume
        ↓
COPY INTO raw Delta table
        ↓
dbt staging views
        ↓
dbt intermediate enrichment
        ↓
dbt marts + snapshots
        ↓
BI / reporting / downstream consumption
```

The design keeps ingestion separate from transformation:

- **Ingestion** is handled by Databricks SQL
- **Transformation** is handled by dbt
- **Orchestration** is handled by GitHub Actions and Databricks Jobs

---

# Setup

## 1. Clone the repository

```bash
git clone https://github.com/YOURUSERNAME/nyc-taxi-dbt.git
cd nyc-taxi-dbt
```

## 2. Create a virtual environment

```bash
python3 -m venv dbt-env
source dbt-env/bin/activate
pip install dbt-databricks
```

## 3. Configure environment variables

```bash
export DATABRICKS_HOST=your-workspace.azuredatabricks.net
export DATABRICKS_TOKEN=your-personal-access-token
export DATABRICKS_HTTP_PATH=/sql/1.0/warehouses/your-warehouse-id
```

You can add these variables to `~/.zshrc` or `~/.bashrc` so they persist across terminal sessions.

## 4. Configure your dbt profile

Copy the profile template:

```bash
cp docs/profile_template.yml ~/.dbt/profiles.yml
```

Then edit the file if required for your Databricks workspace.

## 5. Install dependencies and verify connectivity

```bash
dbt deps
dbt debug
```

`dbt debug` should end with:

```text
All checks passed!
```

---

# Running the Pipeline

### Run all models

```bash
dbt run
```

### Run models followed by tests

```bash
dbt run && dbt test
```

### Run against the production target

```bash
dbt run --target prod
```

### Full rebuild

```bash
dbt run --full-refresh
```

### Source freshness

```bash
dbt source freshness
```

### Execute only tests

```bash
dbt test
```

### Run a single model

```bash
dbt run --select fct_trips_daily
```

### Run a model and all downstream dependencies

```bash
dbt run --select fct_trips_daily+
```

---

# Automated Execution

The repository uses a GitHub Action to trigger a Databricks Job whenever code is pushed to the `main` branch.

Workflow:

- `.github/workflows/trigger_databricks_job.yml`
- GitHub Action **does not execute dbt directly**
- It calls the Databricks Jobs REST API
- Databricks pulls the latest code from GitHub
- The Databricks Job performs ingestion and executes the dbt pipeline

This keeps orchestration lightweight while allowing Databricks to manage execution, retries, compute, and logging.

---

# Ingestion

Raw NYC Taxi files are ingested using:

- `ingestion/ingest_yellow_trips.sql`
- `COPY INTO nyc_taxi.raw.yellow_trips_raw`
- Files uploaded to:

```text
/Volumes/nyc_taxi/raw/landing/trips/
```

### Important behaviour

- `COPY INTO` is idempotent
- Previously ingested files are automatically skipped
- Historical backfills require a deliberate backfill strategy
- Incremental marts assume data arrives in chronological order

For ingestion setup and historical reloads, see:

- `docs/automated_ingestion_setup.md`
- `docs/backfill_playbook.md`

---

# Incremental Strategy

The daily fact table uses an incremental merge strategy.

## Current implementation

- `fct_trips_daily` is materialized as `incremental`
- Merge key: `trip_date + pickup_borough`
- Incremental loading uses a configurable watermark column
- Late-arriving records are handled through a configurable lookback window

### Why this approach?

Incremental loading avoids rebuilding the entire fact table while still reprocessing a configurable number of recent days.

### Current limitation

The current strategy assumes new files contain newer business dates.

If historical files are uploaded after newer data already exists, those older records will **not** automatically appear in the incremental mart.

For historical backfills, follow:

- `docs/backfill_playbook.md`

---

# SCD Framework

The project includes a working SCD Type 2 implementation.

### Snapshot

```text
snapshots/zones_snapshot.sql
```

### Current Dimension

```text
models/marts/dimensions/dim_taxi_zones.sql
```

The snapshot stores complete historical versions, while the dimension exposes only the latest active record for analytical queries.

See:

- `docs/scd_framework_guide.md`

---

# Adding a New Source

The repository is designed to simplify onboarding of additional datasets.

### For sources similar to the existing NYC Taxi example

1. Add the source definition to:

```text
models/staging/_sources.yml
```

2. Add a configuration block under:

```yaml
vars:
  staging_configs:
```

inside `dbt_project.yml`.

3. Create a one-line staging model using:

```jinja
{{ generate_staging_select(...) }}
```

4. Add tests and documentation.

### For sources with different transformation requirements

Reuse the framework but implement a custom staging model where required.

Additional documentation:

- `docs/worked_example_new_source.md`
- `docs/validation_notes.md`

---

# Data Quality

The repository includes:

- `not_null`
- `unique`
- `accepted_values`
- Singular SQL tests
- Source freshness checks

Current custom tests include:

- No future trips
- Unique key validation for `fct_trips_daily`

---

# Documentation

Additional project documentation:

| Document | Description |
|-----------|-------------|
| `docs/architecture.md` | Overall architecture and pipeline design |
| `docs/automated_ingestion_setup.md` | Automated ingestion setup |
| `docs/backfill_playbook.md` | Historical reload and backfill process |
| `docs/scd_framework_guide.md` | SCD Type 1 and Type 2 implementation |
| `docs/validation_notes.md` | Validation approach and testing |
| `docs/worked_example_new_source.md` | Example of onboarding a new dataset |
| `docs/profile_template.yml` | Template dbt profile |

---

# Cost Summary

| Component | Configuration | Cost |
|-----------|---------------|------|
| SQL Warehouse | 2X-Small (Auto Stop: 10 min) | Low / Minimal |
| Staging | Views | No additional storage |
| Intermediate | Ephemeral | No additional storage |
| Marts | Incremental Delta Tables | Minimal |
| Scheduling | GitHub Actions + Databricks Jobs | Low / Minimal |

---

# Key Design Decisions

- SQL Warehouse only (no Spark clusters)
- Pure SQL dbt models
- No Delta Live Tables
- GitHub Actions triggers Databricks Jobs
- dbt performs transformations only
- Ingestion handled separately through Databricks SQL
- Config-driven staging generation
- Watermark-based incremental processing
- SCD Type 2 implemented using dbt snapshots
- Documentation maintained alongside code

---

# Development Workflow

For development or demonstration resets:

1. Clear the raw table
2. Remove existing mart tables
3. Upload source files in chronological order
4. Trigger the Databricks Job

For historical backfills, use the documented procedure instead of relying on a standard incremental run.

---

# Future Enhancements

Potential improvements include:

- Additional source templates
- Generic dimension framework
- Expanded snapshot coverage
- More reusable data quality macros
- Elementary integration
- Monitoring and alerting
- Additional mart templates
- Metadata-driven model generation
- Support for Auto Loader alongside `COPY INTO`