# SCD Framework — Decision Guide

## The Two Strategies, Plainly

**SCD Type 1 — overwrite, no history.**
When a dimension's attributes change, the old value is gone. You always see
the current value only. This is just a normal dbt `incremental` model with
`incremental_strategy='merge'` — nothing special needs to be built, because
dbt's native merge strategy already IS SCD Type 1. Match on the business
key, update the attribute columns, done.

**SCD Type 2 — full history, nothing ever overwritten.**
Every change creates a new row; the old row gets closed out with a
`dbt_valid_to` timestamp instead of being modified. This requires a real
dbt **snapshot**, not an incremental model — snapshots are dbt's
purpose-built mechanism for this exact pattern. See `zones_snapshot.sql`
for the implementation, and `dim_taxi_zones.sql` for how to expose a
"current only" view on top of it for normal joins.

## Choosing Per Dimension — `dimension_configs` (Governance, Not Enforcement)

Add this to `dbt_project.yml` vars, alongside `staging_configs` and
`incremental_configs`. This is documentation-as-config — it records the
DECISION for each dimension in one auditable place, even though the actual
mechanism (snapshot vs. plain incremental) still has to be built per
dimension, same honest limitation as the staging generator.

```yaml
vars:
  dimension_configs:
    taxi_zones:
      scd_type: 2
      business_key: location_id
      tracked_columns: [zone_name, borough, service_zone]
      reason: "Zone reassignment/renaming is real and needs to be auditable"
```

When someone asks "why does this dimension have history and that one
doesn't," this config block is the answer — a deliberate, recorded decision,
not an inconsistency.

## Worked Example — Adding a New SCD Type 1 Dimension

Say a `vendor_lookup` reference table gets added (vendor ID -> vendor name,
a small static table like taxi zones, but where you genuinely don't care
about history — a renamed vendor just becomes the new name going forward).

### 1. Record the decision in dbt_project.yml

```yaml
vars:
  dimension_configs:
    vendors:
      scd_type: 1
      business_key: vendor_id
      reason: "Vendor renames are rare and historical accuracy isn't needed"
```

### 2. Write the model — a plain incremental merge, no snapshot needed

`models/marts/dimensions/dim_vendors.sql`:
```sql
{{ config(
    materialized='incremental',
    unique_key='vendor_id',
    incremental_strategy='merge'
) }}

SELECT
    vendor_id,
    vendor_name

FROM {{ ref('stg_vendors') }}

{{ apply_incremental_watermark(watermark_column='vendor_id', late_arrival_days=0) }}
```

That's the entire SCD Type 1 implementation. No new macro, no new pattern —
it reuses the same incremental watermark macro already built for fact tables.

## Worked Example — Adding a New SCD Type 2 Dimension

Say a `driver_status` dimension needs full history (a driver's active/inactive
status over time genuinely matters for historical reporting).

### 1. Record the decision

```yaml
vars:
  dimension_configs:
    driver_status:
      scd_type: 2
      business_key: driver_id
      tracked_columns: [status, license_type]
      reason: "Historical driver status is needed for compliance reporting"
```

### 2. Write the snapshot — copy zones_snapshot.sql's shape exactly

`snapshots/driver_status_snapshot.sql`:
```sql
{% snapshot driver_status_snapshot %}
{{
    config(
      unique_key='driver_id',
      strategy='check',
      check_cols=['status', 'license_type'],
    )
}}
SELECT driver_id, status, license_type
FROM {{ source('raw', 'driver_status_raw') }}
{% endsnapshot %}
```

### 3. Write the current-state view — copy dim_taxi_zones.sql's shape exactly

`models/marts/dimensions/dim_driver_status.sql`:
```sql
SELECT
    driver_id, status, license_type,
    dbt_valid_from AS effective_from,
    dbt_updated_at AS last_changed_at
FROM {{ ref('driver_status_snapshot') }}
WHERE dbt_valid_to IS NULL
```

## What's Genuinely Reusable vs. What Still Needs Per-Dimension Work

Reusable, zero changes needed: `apply_incremental_watermark()` macro, the
`dimension_configs` documentation pattern, the "snapshot + current view"
two-file shape for any SCD2 dimension.

Still needs per-dimension authoring: the snapshot file itself and the
current-view file itself — dbt has no mechanism to generate N snapshots
from one config-driven file, same structural limitation as staging models.
What you get from this framework is a **proven, consistent shape** to copy
for dimension #2 through #100, not zero new files.
