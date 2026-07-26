-- ─────────────────────────────────────────────────────────────────────────
-- Automated ingestion for yellow taxi trip data.
--
-- This file is executed as a Databricks Job SQL task, on the SQL Warehouse,
-- triggered automatically by a File Arrival trigger watching this exact
-- Volume path. No human runs this by hand — that is the entire point.
--
-- Why COPY INTO is safe to trigger repeatedly / on every file arrival event:
--   - It tracks which files it has already loaded internally, per target
--     table, and silently skips anything already ingested.
--   - It only fails to detect a genuinely-new file as "new" if that file
--     was MOVED after being loaded once under a different path — which is
--     a self-inflicted edge case (we hit this exact issue during manual
--     testing earlier in this project). New files landing fresh in this
--     folder, which is the real production pattern, are handled correctly.
--
-- Do NOT move or rename files inside trips/ after they've landed here.
-- If a historical backfill needs re-ingesting under a new path, use the
-- procedure in docs/backfill_playbook.md instead of relying on this to
-- auto-detect it.
-- ─────────────────────────────────────────────────────────────────────────

COPY INTO nyc_taxi.raw.yellow_trips_raw
FROM '/Volumes/nyc_taxi/raw/landing/trips/'
FILEFORMAT = PARQUET
COPY_OPTIONS ('mergeSchema' = 'true');