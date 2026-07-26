# Automated Ingestion Setup — File Arrival Triggers a Full Pipeline Run

Goal: drop a new month's parquet file into the Volume, and within minutes
the mart tables (and anything reading from them) reflect it — with zero
manual `COPY INTO`, zero manual `dbt run`, zero human in the loop.

## Step 1 — Add the SQL Ingestion Task to Your Existing Job

You already have a Databricks Job running the dbt task. Add a NEW task to
that same Job, positioned to run BEFORE the existing dbt task.

1. Open your existing Job (`dbt_nyc_taxi_daily` or whatever you named it)
2. Click **Tasks** tab → **+ Add task**
3. Configure:
   - **Task name:** `ingest_raw_data`
   - **Type:** `SQL`
   - **SQL task:** `File`
   - **Source:** same Git provider / branch you already use for the dbt task
   - **Path:** `ingestion/ingest_yellow_trips.sql`
   - **SQL warehouse:** your existing `dbt-warehouse`
4. Click **Create task**

## Step 2 — Make the dbt Task Depend On the Ingestion Task

1. Click into your EXISTING dbt task (the one running `dbt build`)
2. Find **Depends on** → set it to `ingest_raw_data`
3. Save

This ordering matters: if `COPY INTO` fails (bad file, schema mismatch,
whatever), dbt never runs on incomplete/broken raw data. The Job stops at
the failed task instead of silently building marts on stale data.

Your Job's task graph should now look like:
```
ingest_raw_data (SQL, COPY INTO)
        │
        ▼
dbt_build (dbt task, depends on ingest_raw_data)
```

## Step 3 — Add the File Arrival Trigger

1. On the Job's main page, go to **Schedules & Triggers**
2. Click **Add trigger**
3. Trigger type: **File arrival**
4. **Storage location:** `/Volumes/nyc_taxi/raw/landing/trips/`
5. Save

**IMPORTANT — verify this is actually available on your Free Edition
workspace before relying on it.** File arrival triggers have historically
had tighter availability restrictions than time-based schedules across
Databricks tiers, and Free Edition's exact feature set changes over time.
If the "File arrival" option doesn't appear, or errors when you try to
save it pointing at a Volume path, use the fallback below instead — it
achieves the same practical outcome with one small trade-off.

## Fallback — If File Arrival Isn't Available: Tight Time-Based Polling

If Step 3 isn't available on your workspace tier, add a second **Scheduled**
trigger instead, set to run frequently:

1. **Add trigger** → **Scheduled**
2. Cron: every 15 or 30 minutes (`*/15 * * * *`)
3. Save

This isn't truly event-driven, but the practical difference is small: new
data is picked up within 15-30 minutes of landing instead of near-instantly.
`COPY INTO`'s idempotency means running it every 15 minutes with no new file
present is a safe, cheap no-op — it costs a brief SQL Warehouse wake-up, not
a wasted full reprocessing.

Keep your existing daily 6 AM trigger in place regardless of which option
you use — that stays as a reliability backstop even if a file-arrival or
polling trigger is ever missed for any reason.

## Step 4 — End-to-End Validation

This is the actual proof the automation works, not just that each piece
works in isolation.

1. Confirm current state before the test:
   ```sql
   SELECT MAX(trip_date) FROM nyc_taxi.prod_marts.fct_trips_daily;
   ```

2. Upload a genuinely new month's parquet file directly into
   `/Volumes/nyc_taxi/raw/landing/trips/` — through the Catalog Explorer UI,
   exactly like a real new-data-arrival event, not through any dbt or SQL
   command.

3. Do NOT run anything manually. Wait.

4. Check the Job's run history (**Jobs & Pipelines** → your job → **Runs**)
   — a new run should appear automatically, triggered by the file arrival
   (or the next polling interval, if using the fallback), with no manual
   "Run now" click from you.

5. Once that run shows green, re-check:
   ```sql
   SELECT MAX(trip_date) FROM nyc_taxi.prod_marts.fct_trips_daily;

   SELECT trip_date, pickup_borough, total_trips, _dbt_loaded_at
   FROM nyc_taxi.prod_marts.fct_trips_daily
   ORDER BY trip_date DESC
   LIMIT 10;
   ```

If `MAX(trip_date)` advanced to cover the new month, and `_dbt_loaded_at`
on those new rows is recent, timestamped right after your upload — that is
the complete, proven, end-to-end automated pipeline: file lands, ingestion
runs itself, dbt runs itself, marts update themselves, with zero commands
typed by a human after the file was uploaded.
