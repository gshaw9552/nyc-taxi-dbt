# Backfill Playbook — Handling Data Older Than the Current Watermark

## The Real Limitation This Documents

A forward-only watermark (`WHERE watermark_column >= MAX(watermark_column) - N days`)
is the correct, cheap strategy for the common case: new data arriving with a
date at or after whatever's already in the table. It is NOT designed to pick
up data that is OLDER than the current max — and no amount of macro cleverness
changes that; it's a fundamental property of "look backward N days from the max."

This is exactly what happened during this project's own testing: April data
was loaded and incrementally processed first, establishing April 30th as the
watermark. When March data was added to the same raw table afterward, a plain
`dbt run` on the incremental model did NOT pick it up — because March is
BEFORE the existing watermark, outside the 3-day lookback window entirely.

That is not a bug. It is the expected, correct behavior of a watermark
strategy. The mistake to avoid is reaching for `--full-refresh` as the
default fix — on a large table, that reprocesses everything, including
months of already-correct data, purely to backfill a narrow date range.

## The Correct Fix: A Targeted Partial Backfill, Not a Blind Full Refresh

Use `dbt run` with an explicit variable override that temporarily widens the
watermark lookback far enough to cover the backfill range, run once, then
return to normal.

### Step 1 — Confirm the actual gap

```sql
SELECT MIN(trip_date), MAX(trip_date)
FROM nyc_taxi.raw.yellow_trips_raw;
```

Know exactly how far back the new data goes before choosing a lookback value.

### Step 2 — Run once with an overridden late_arrival_days, not --full-refresh

```bash
dbt run --select fct_trips_daily \
  --vars '{"incremental_configs": {"fct_trips_daily": {"watermark_column": "trip_date", "late_arrival_days": 45}}}'
```

This uses the SAME incremental merge logic — no full table rewrite — just a
wider one-time lookback window that reaches back far enough to include the
backfilled month. The `--vars` flag overrides the project's vars for this
invocation only; your dbt_project.yml stays untouched.

### Step 3 — Return to normal on the next scheduled run

No action needed — the next plain `dbt run` (no `--vars` override) reads the
normal `late_arrival_days: 3` from dbt_project.yml again automatically.

### Step 4 — Verify the backfill actually landed

```sql
SELECT
    DATE_TRUNC('MONTH', trip_date) AS month,
    COUNT(*) AS row_count,
    MIN(_dbt_loaded_at) AS first_loaded,
    MAX(_dbt_loaded_at) AS last_loaded
FROM nyc_taxi.dev_marts.fct_trips_daily
GROUP BY 1 ORDER BY 1;
```

The backfilled month should now show a recent `_dbt_loaded_at`, and every
OTHER month's `_dbt_loaded_at` should be untouched from whenever it was last
processed — proving the backfill was targeted, not a full rebuild.

## When a Real Full Refresh IS Still Justified

Be honest about this rather than pretending the watermark macro makes
`--full-refresh` obsolete entirely:

- The model's SELECT logic or grain changes (new/removed group-by column)
- The `unique_key` changes
- Data corruption is suspected across the whole table, not a known date range
- A first-ever run establishing the initial incremental baseline

A wide date-range backfill from new historical data landing is NOT one of
these cases, and should always use the targeted `--vars` override above instead.
