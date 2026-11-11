# Module 3: Production Data Engineering Patterns

> This module covers battle-tested SQL patterns used in production data pipelines. Each pattern includes brief explanations, dialect-agnostic syntax (with cloud-warehouse notes where engines diverge), realistic DE scenarios with sample inputs/outputs, and pitfalls that surface in interviews and on-call debugging.

---

## Table of Contents

1. [Deduplication](#1-deduplication)
2. [Change Data Capture (CDC) & Slowly Changing Dimensions (SCD)](#2-change-data-capture-cdc--slowly-changing-dimensions-scd)
3. [Gaps & Islands](#3-gaps--islands)
4. [Sessionization](#4-sessionization)
5. [Semi-Structured Data (JSON)](#5-semi-structured-data-json)
6. [Idempotent Data Ingestion & Upserts](#6-idempotent-data-ingestion--upserts)
7. [Date, Time & Calendar Spines](#7-date-time--calendar-spines)

---

## 1. Deduplication

### Explanation

Duplicate records are the most common data quality issue in production pipelines, caused by Kafka at-least-once delivery, replayed CDC logs, overlapping batch extracts, and late-arriving data. Window-based deduplication uses `ROW_NUMBER()` partitioned by the business key to isolate exactly one winning row per entity. Pairing a business timestamp with an ingestion tie-breaker guarantees deterministic output across re-runs, and scanning a rolling lookback window catches late-arriving duplicates.

### When to Use This

- After ingesting from an at-least-once message bus (Kafka, Pub/Sub, Kinesis)
- When merging overlapping daily/hourly batch extracts or webhook retries
- Before running a `MERGE INTO` statement (which fails if staging contains duplicate keys)
- When handling late-arriving updates over a rolling reprocessing window

### Quick-Reference Syntax

```sql
-- 1. Window-based deduplication with deterministic tie-breaking
WITH ranked AS (
    SELECT
        id,
        payload,
        updated_at,
        _ingested_at,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY updated_at DESC, _ingested_at DESC, _source_offset DESC
        ) AS rn
    FROM raw_events
)
SELECT id, payload, updated_at, _ingested_at
FROM ranked
WHERE rn = 1;

-- 2. Handling late-arriving data via a rolling lookback window (e.g., 3 days)
WITH windowed_dedup AS (
    SELECT
        order_id,
        status,
        updated_at,
        _ingested_at,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY updated_at DESC, _ingested_at DESC
        ) AS rn
    FROM raw_orders
    WHERE updated_at >= CURRENT_DATE - INTERVAL '3' DAY
       OR _ingested_at >= CURRENT_DATE - INTERVAL '3' DAY
)
SELECT order_id, status, updated_at, _ingested_at
FROM windowed_dedup
WHERE rn = 1;
```

*(Note: Snowflake, DuckDB, and BigQuery support `QUALIFY ROW_NUMBER() OVER (...) = 1` to avoid the outer CTE.)*

### Realistic Scenario

**Context:** An e-commerce platform ingests order updates from Kafka into `raw_orders`. Due to a consumer rebalance, order `1001` at `14:00:00` was delivered twice at different ingestion times, and a late-arriving status correction for order `1003` from yesterday landed during today's run.

**Sample Data — `raw_orders`:**

| order_id | customer_id | amount | status    | updated_at          | _ingested_at        |
|----------|-------------|--------|-----------|---------------------|---------------------|
| 1001     | 42          | 99.99  | pending   | 2024-03-02 10:00:00 | 2024-03-02 10:05:00 |
| 1001     | 42          | 99.99  | shipped   | 2024-03-02 14:00:00 | 2024-03-02 14:05:00 |
| 1001     | 42          | 99.99  | shipped   | 2024-03-02 14:00:00 | 2024-03-02 15:00:00 |
| 1002     | 87          | 49.50  | delivered | 2024-03-02 09:00:00 | 2024-03-02 09:05:00 |
| 1003     | 19          | 25.00  | pending   | 2024-03-01 23:50:00 | 2024-03-01 23:55:00 |
| 1003     | 19          | 25.00  | cancelled | 2024-03-01 23:58:00 | 2024-03-02 06:10:00 |

**Query (Lookback + Deterministic Tie-Breaking):**

```sql
WITH ranked AS (
    SELECT
        order_id,
        customer_id,
        amount,
        status,
        updated_at,
        _ingested_at,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY updated_at DESC, _ingested_at DESC
        ) AS rn
    FROM raw_orders
    WHERE _ingested_at >= TIMESTAMP '2024-03-01 00:00:00'
)
SELECT order_id, customer_id, amount, status, updated_at, _ingested_at
FROM ranked
WHERE rn = 1
ORDER BY order_id;
```

**Expected Output:**

| order_id | customer_id | amount | status    | updated_at          | _ingested_at        |
|----------|-------------|--------|-----------|---------------------|---------------------|
| 1001     | 42          | 99.99  | shipped   | 2024-03-02 14:00:00 | 2024-03-02 15:00:00 |
| 1002     | 87          | 49.50  | delivered | 2024-03-02 09:00:00 | 2024-03-02 09:05:00 |
| 1003     | 19          | 25.00  | cancelled | 2024-03-01 23:58:00 | 2024-03-02 06:10:00 |

Notice how `_ingested_at DESC` deterministically picks the `15:00:00` copy of order `1001`, and filtering on `_ingested_at` (rather than `updated_at`) ensures the late-arriving `1003` cancellation is captured even though its business timestamp belongs to the prior day.

> [!WARNING]
> **Gotchas & Pitfalls:**
> - **Non-deterministic tie-breaking:** If two rows share the same `updated_at`, `ROW_NUMBER()` picks one arbitrarily. Always append monotonic tie-breakers (`_ingested_at DESC`, `_kafka_offset DESC`, or a surrogate event ID).
> - **`RANK()` vs `ROW_NUMBER()`:** `RANK()` and `DENSE_RANK()` assign `1` to every tied row, so `WHERE rn = 1` will still emit duplicates. Always use `ROW_NUMBER()`.
> - **Filtering late data by business date:** If today's batch filters `WHERE DATE(updated_at) = CURRENT_DATE`, a late update whose `updated_at` was yesterday will be ignored forever. Filter staging by `_ingested_at` and use a lookback window (or `MERGE`) against the target.
> - **`NULL` timestamps sort first in `DESC` in some dialects:** PostgreSQL and Oracle place `NULL` values *first* in `ORDER BY col DESC` unless you specify `NULLS LAST`. Explicitly write `ORDER BY updated_at DESC NULLS LAST` when timestamps can be null.

---

## 2. Change Data Capture (CDC) & Slowly Changing Dimensions (SCD)

### Explanation

Change Data Capture (CDC) streams every insert, update, and delete from an operational database into the warehouse. **SCD Type 1** overwrites existing attributes in place without keeping history, while **SCD Type 2** preserves full historical versions using `valid_from`, `valid_to`, and `is_current` columns. When CDC events arrive out of order, rebuilding affected keys with `LEAD()` cleanly repairs historical intervals without overlapping date ranges.

### When to Use This

- **SCD Type 1:** Correcting typos, fixing bad source data, or tracking attributes where only the latest value matters (e.g., `last_login_ip`)
- **SCD Type 2:** Regulatory/audit requirements, subscription tier history, pricing history, and point-in-time ("as-of") joins for historical facts
- **Out-of-order CDC reconstruction:** Backfilling late CDC batches or repairing timelines from an append-only CDC event log

### Quick-Reference Syntax

**SCD Type 1 — Overwrite (No History):**

```sql
MERGE INTO dim_customer AS tgt
USING (
    SELECT customer_id, name, email, updated_at
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at DESC) AS rn
        FROM staging_customer
    ) d
    WHERE rn = 1
) AS src
  ON tgt.customer_id = src.customer_id
WHEN MATCHED AND src.updated_at > tgt.updated_at THEN
    UPDATE SET
        name       = src.name,
        email      = src.email,
        updated_at = src.updated_at
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, email, updated_at)
    VALUES (src.customer_id, src.name, src.email, src.updated_at);
```

**SCD Type 2 — Incremental Close + Insert (New & Changed Rows):**

```sql
-- Step 1: Close out active records when tracked attributes actually changed
-- Guard against out-of-order stale updates via src.effective_date > dim_customer.valid_from
UPDATE dim_customer
SET
    valid_to   = (
        SELECT src.effective_date
        FROM staging_customer src
        WHERE src.customer_id = dim_customer.customer_id
    ),
    is_current = FALSE
WHERE is_current = TRUE
  AND EXISTS (
      SELECT 1
      FROM staging_customer src
      WHERE src.customer_id = dim_customer.customer_id
        AND src.effective_date > dim_customer.valid_from
        AND (
            dim_customer.name  IS DISTINCT FROM src.name
         OR dim_customer.email IS DISTINCT FROM src.email
        )
  );

-- Step 2: Insert new versions (both brand-new customers AND newly closed customers)
INSERT INTO dim_customer (customer_id, name, email, valid_from, valid_to, is_current)
SELECT
    src.customer_id,
    src.name,
    src.email,
    src.effective_date,
    DATE '9999-12-31',
    TRUE
FROM staging_customer src
WHERE NOT EXISTS (
    SELECT 1
    FROM dim_customer tgt
    WHERE tgt.customer_id = src.customer_id
      AND tgt.is_current = TRUE
);
```

**SCD Type 2 — Handling Out-of-Order CDC Records (Timeline Reconstruction via `LEAD`):**

```sql
-- Recompute clean, non-overlapping SCD2 intervals for affected keys
WITH deduped_cdc AS (
    SELECT
        customer_id, name, email, effective_date,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, effective_date
            ORDER BY _ingested_at DESC
        ) AS rn
    FROM cdc_customer_events
),
changes_only AS (
    -- Optional: collapse consecutive no-op events where tracked attributes didn't change
    SELECT
        customer_id, name, email, effective_date,
        LAG(name)  OVER (PARTITION BY customer_id ORDER BY effective_date) AS prev_name,
        LAG(email) OVER (PARTITION BY customer_id ORDER BY effective_date) AS prev_email
    FROM deduped_cdc
    WHERE rn = 1
)
SELECT
    customer_id,
    name,
    email,
    effective_date AS valid_from,
    COALESCE(
        LEAD(effective_date) OVER (PARTITION BY customer_id ORDER BY effective_date),
        DATE '9999-12-31'
    ) AS valid_to,
    CASE
        WHEN LEAD(effective_date) OVER (PARTITION BY customer_id ORDER BY effective_date) IS NULL
        THEN TRUE ELSE FALSE
    END AS is_current
FROM changes_only
WHERE name  IS DISTINCT FROM prev_name
   OR email IS DISTINCT FROM prev_email
   OR (prev_name IS NULL AND prev_email IS NULL);
```

### Realistic Scenario

**Context:** Customer `501` signed up in 2023 and updated their email in June 2024. However, a delayed CDC event from a regional microservice (`2024-02-01`) arrives late in July. Rebuilding `501`'s history from the CDC log inserts the missing interval seamlessly without corrupting the current record.

**Sample Data — `cdc_customer_events` (for `customer_id = 501`):**

| customer_id | name       | email             | effective_date | _ingested_at        |
|-------------|------------|-------------------|----------------|---------------------|
| 501         | Alice Chen | alice@old.com     | 2023-01-01     | 2023-01-01 08:00:00 |
| 501         | Alice Chen | alice@newmail.com | 2024-06-15     | 2024-06-15 09:10:00 |
| 501         | Alice Chen | alice@mid.com     | 2024-02-01     | 2024-07-02 12:00:00 |

**Query:** Run the `LEAD()` timeline reconstruction query above on `cdc_customer_events`.

**Expected Output — `dim_customer`:**

| customer_id | name       | email             | valid_from | valid_to   | is_current |
|-------------|------------|-------------------|------------|------------|------------|
| 501         | Alice Chen | alice@old.com     | 2023-01-01 | 2024-02-01 | FALSE      |
| 501         | Alice Chen | alice@mid.com     | 2024-02-01 | 2024-06-15 | FALSE      |
| 501         | Alice Chen | alice@newmail.com | 2024-06-15 | 9999-12-31 | TRUE       |

**Point-in-time ("as-of") query — "What was Alice's email on `2024-03-01`?"**

```sql
SELECT customer_id, email
FROM dim_customer
WHERE customer_id = 501
  AND DATE '2024-03-01' >= valid_from
  AND DATE '2024-03-01' <  valid_to;
-- Returns: alice@mid.com
```

> [!WARNING]
> **Gotchas & Pitfalls:**
> - **Out-of-order CDC overwrites:** An incremental SCD2 that blindly closes `is_current = TRUE` and inserts the incoming event will mark the stale `2024-02-01` event as `is_current = TRUE` and create invalid intervals (`valid_from > valid_to`). Either reject events older than `tgt.valid_from` or rebuild affected keys with `LEAD()`.
> - **`NULL` breaks `<>` comparisons:** `NULL <> 'alice@new.com'` evaluates to `UNKNOWN`, so changes from `NULL` to a value are silently ignored. Always use `IS DISTINCT FROM` (or `COALESCE`).
> - **Half-open `[valid_from, valid_to)` vs closed ranges:** Always use `>= valid_from AND < valid_to` for half-open intervals. Using `BETWEEN valid_from AND valid_to` matches *two* rows on boundary dates (`2024-02-01`) and causes fact-table fan-out!
> - **Forgetting brand-new keys in Step 2:** Joining `staging` to `dim_customer` on `tgt.is_current = FALSE` misses brand-new entities that never existed in `dim_customer`. Use `NOT EXISTS (... AND tgt.is_current = TRUE)` instead.

---

## 3. Gaps & Islands

### Explanation

The Gaps & Islands pattern groups contiguous sequences (islands) of rows separated by breaks (gaps), such as consecutive active user days or uninterrupted server uptime windows. Subtracting a `ROW_NUMBER()` from a sequential value (like a date or integer ID) yields a constant group identifier across every contiguous island. For non-sequential status tracking, subtracting a partitioned `ROW_NUMBER()` from a global `ROW_NUMBER()` isolates contiguous runs of identical state.

### When to Use This

- Computing user login streaks, longest consecutive active days, or retention cohorts
- Grouping contiguous server uptime/downtime checks or subscription status periods
- Detecting missing sequence gaps in invoice IDs, sensor readings, or daily partition loads
- Collapsing noisy row-level status logs into start/end validity ranges

### Quick-Reference Syntax

```sql
-- Pattern A: Consecutive date islands (streaks)
WITH distinct_dates AS (
    SELECT DISTINCT user_id, activity_date
    FROM user_logins
),
numbered AS (
    SELECT
        user_id,
        activity_date,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY activity_date) AS rn
    FROM distinct_dates
),
islands AS (
    SELECT
        user_id,
        activity_date,
        activity_date - (rn * INTERVAL '1' DAY) AS island_id
    FROM numbered
)
SELECT
    user_id,
    MIN(activity_date) AS streak_start,
    MAX(activity_date) AS streak_end,
    COUNT(*)           AS streak_days
FROM islands
GROUP BY user_id, island_id
ORDER BY user_id, streak_start;

-- Pattern B: Contiguous status ranges (double ROW_NUMBER trick)
WITH status_groups AS (
    SELECT
        server_id,
        status,
        check_time,
        ROW_NUMBER() OVER (PARTITION BY server_id ORDER BY check_time)
      - ROW_NUMBER() OVER (PARTITION BY server_id, status ORDER BY check_time) AS grp
    FROM server_health_checks
)
SELECT
    server_id,
    status,
    MIN(check_time) AS period_start,
    MAX(check_time) AS period_end,
    COUNT(*)        AS check_count
FROM status_groups
GROUP BY server_id, status, grp
ORDER BY server_id, period_start;
```

### Realistic Scenario 1 — Consecutive Active Days (Streaks)

**Context:** A product team wants every login streak (`streak_start`, `streak_end`, `streak_days`) per user from `user_logins`. Note that user `1` logged in twice on `2024-03-02`, so we must deduplicate dates first.

**Sample Data — `user_logins`:**

| user_id | activity_date |
|---------|---------------|
| 1       | 2024-03-01    |
| 1       | 2024-03-02    |
| 1       | 2024-03-02    |
| 1       | 2024-03-03    |
| 1       | 2024-03-06    |
| 1       | 2024-03-07    |
| 2       | 2024-03-01    |
| 2       | 2024-03-03    |

**Query:** Pattern A above.

**Expected Output:**

| user_id | streak_start | streak_end | streak_days |
|---------|--------------|------------|-------------|
| 1       | 2024-03-01   | 2024-03-03 | 3           |
| 1       | 2024-03-06   | 2024-03-07 | 2           |
| 2       | 2024-03-01   | 2024-03-01 | 1           |
| 2       | 2024-03-03   | 2024-03-03 | 1           |

### Realistic Scenario 2 — Contiguous Status Ranges (Server Uptime)

**Context:** An infrastructure pipeline polls server status every 5 minutes and needs to compress raw health-check rows into contiguous `UP`/`DOWN` intervals.

**Sample Data — `server_health_checks`:**

| server_id | check_time          | status |
|-----------|---------------------|--------|
| web-01    | 2024-03-01 00:00:00 | UP     |
| web-01    | 2024-03-01 00:05:00 | UP     |
| web-01    | 2024-03-01 00:10:00 | DOWN   |
| web-01    | 2024-03-01 00:15:00 | DOWN   |
| web-01    | 2024-03-01 00:20:00 | UP     |

**Query:** Pattern B above.

**Expected Output:**

| server_id | status | period_start        | period_end          | check_count |
|-----------|--------|---------------------|---------------------|-------------|
| web-01    | UP     | 2024-03-01 00:00:00 | 2024-03-01 00:05:00 | 2           |
| web-01    | DOWN   | 2024-03-01 00:10:00 | 2024-03-01 00:15:00 | 2           |
| web-01    | UP     | 2024-03-01 00:20:00 | 2024-03-01 00:20:00 | 1           |

> [!WARNING]
> **Gotchas & Pitfalls:**
> - **Duplicate dates break the island math:** Two rows for the same `(user_id, activity_date)` advance `ROW_NUMBER()` by 2 while the date advances by 1, splitting one streak into two. Always apply `SELECT DISTINCT` (or `DATE_TRUNC` + `DISTINCT`) first.
> - **Missing `status` in `GROUP BY` (Pattern B):** Two different statuses can temporarily share the same `grp` value (`rn_all - rn_status`). Always group by `(server_id, status, grp)`.
> - **Dialect-specific interval multiplication:** `rn * INTERVAL '1' DAY` works in PostgreSQL/DuckDB, whereas BigQuery requires `DATE_SUB(activity_date, INTERVAL rn DAY)` and Snowflake requires `DATEADD('day', -rn, activity_date)`.
> - **Tied timestamps in status tracking:** If two health checks share an identical `check_time`, the two `ROW_NUMBER()` calls may break ties differently. Include a secondary unique column (`ORDER BY check_time, check_id`) in both window clauses, or use a single-pass `LAG(status)` + cumulative `SUM()` change flag.

---

## 4. Sessionization

### Explanation

Sessionization partitions a continuous stream of user or device events into discrete sessions based on an inactivity timeout (commonly 30 minutes for clickstreams). You compute the elapsed time since the previous event using `LAG()`, raise a `1/0` flag whenever the gap exceeds the timeout (or on the first event), and run a cumulative `SUM()` of that flag to mint sequential per-user session IDs.

### When to Use This

- Web and mobile clickstream analytics (session duration, bounce rate, pages per session)
- IoT and fleet telemetry (grouping sensor pings into active trips or machine cycles)
- Customer support and call-center interaction grouping
- Fraud detection (burst activity windows per account)

### Quick-Reference Syntax

```sql
WITH lagged AS (
    SELECT
        user_id,
        event_id,
        event_time,
        event_type,
        LAG(event_time) OVER (
            PARTITION BY user_id
            ORDER BY event_time, event_id
        ) AS prev_event_time
    FROM clickstream
),
flagged AS (
    SELECT
        user_id,
        event_id,
        event_time,
        event_type,
        prev_event_time,
        CASE
            WHEN prev_event_time IS NULL THEN 1
            -- ANSI interval comparison: works cleanly across engines without EPOCH tricks
            WHEN event_time - prev_event_time > INTERVAL '30' MINUTE THEN 1
            ELSE 0
        END AS is_new_session
    FROM lagged
),
sessionized AS (
    SELECT
        user_id,
        event_id,
        event_time,
        event_type,
        is_new_session,
        SUM(is_new_session) OVER (
            PARTITION BY user_id
            ORDER BY event_time, event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS user_session_seq
    FROM flagged
)
SELECT
    user_id,
    user_id || '-' || CAST(user_session_seq AS VARCHAR(20)) AS global_session_id,
    MIN(event_time) AS session_start,
    MAX(event_time) AS session_end,
    COUNT(*)        AS event_count
FROM sessionized
GROUP BY user_id, user_session_seq;
```

*(Note: For engines without direct timestamp subtraction returning an interval, use `TIMESTAMP_DIFF(event_time, prev_event_time, MINUTE) > 30` in BigQuery or `DATEDIFF('minute', prev_event_time, event_time) > 30` in Snowflake/SQL Server.)*

### Realistic Scenario

**Context:** A product analytics pipeline must assign 30-minute inactivity sessions to `clickstream` events and compute per-session boundaries and event counts.

**Sample Data — `clickstream`:**

| user_id | event_id | event_time          | event_type |
|---------|----------|---------------------|------------|
| A       | e1       | 2024-03-01 09:00:00 | page_view  |
| A       | e2       | 2024-03-01 09:05:00 | click      |
| A       | e3       | 2024-03-01 09:12:00 | page_view  |
| A       | e4       | 2024-03-01 10:00:00 | page_view  |
| A       | e5       | 2024-03-01 10:10:00 | click      |
| B       | e6       | 2024-03-01 09:30:00 | page_view  |

**Intermediate Window Output (`sessionized`):**

| user_id | event_id | event_time          | event_type | is_new_session | user_session_seq |
|---------|----------|---------------------|------------|----------------|------------------|
| A       | e1       | 2024-03-01 09:00:00 | page_view  | 1              | 1                |
| A       | e2       | 2024-03-01 09:05:00 | click      | 0              | 1                |
| A       | e3       | 2024-03-01 09:12:00 | page_view  | 0              | 1                |
| A       | e4       | 2024-03-01 10:00:00 | page_view  | 1              | 2                |
| A       | e5       | 2024-03-01 10:10:00 | click      | 0              | 2                |
| B       | e6       | 2024-03-01 09:30:00 | page_view  | 1              | 1                |

**Expected Output (Session Summary):**

| user_id | global_session_id | session_start       | session_end         | event_count |
|---------|-------------------|---------------------|---------------------|-------------|
| A       | A-1               | 2024-03-01 09:00:00 | 2024-03-01 09:12:00 | 3           |
| A       | A-2               | 2024-03-01 10:00:00 | 2024-03-01 10:10:00 | 2           |
| B       | B-1               | 2024-03-01 09:30:00 | 2024-03-01 09:30:00 | 1           |

> [!WARNING]
> **Gotchas & Pitfalls:**
> - **Default `RANGE` frame on tied timestamps:** If you omit `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` and two events share the exact same `event_time`, the default `RANGE` frame evaluates peers together, which can produce unexpected cumulative totals without a unique tie-breaker (`event_id`).
> - **`DATEDIFF('minute', ...)` truncation trap:** In Snowflake/SQL Server, `DATEDIFF('minute', '09:00:59', '09:30:01')` counts minute boundaries crossed (`30`), whereas `09:00:01` to `09:30:59` also returns `30` (almost 31 minutes!). Compare seconds (`> 1800`) or native intervals (`> INTERVAL '30' MINUTE`) for exact 30-minute thresholds.
> - **Per-user ID vs global ID:** Cumulative `SUM` starts at `1` for every user. Never `GROUP BY user_session_seq` alone—always group by `(user_id, user_session_seq)` or construct a composite/hashed `global_session_id`.
> - **Incremental batch boundary splitting:** If you sessionize daily partitions independently, a session running from `23:55` to `00:10` gets split in half. Include a buffer overlap (e.g., `lookback >= timeout`) before the batch cutoff.

---

## 5. Semi-Structured Data (JSON)

### Explanation

Pipelines regularly land raw JSON documents from REST APIs, webhooks, and document stores before modeling them into typed relational tables. SQL engines provide path operators and ANSI functions (`JSON_VALUE`, `JSON_QUERY`) to extract scalar keys, alongside table functions (`UNNEST`, `LATERAL FLATTEN`, `jsonb_array_elements`, `JSON_TABLE`) to explode nested arrays into rows. Filtering array elements is performed either after flattening in a `WHERE` clause or inline via JSONPath predicates.

### When to Use This

- Bronze-to-Silver flattening of raw API payloads, webhook logs, or Kafka JSON envelopes
- Extracting deeply nested attributes while casting them safely into typed columns
- Exploding one-to-many nested arrays (order line items, user roles, event tags)
- Filtering arrays to isolate specific items or identify parent records matching an array condition

### Quick-Reference Syntax

**1. Key Extraction & Typing (ANSI & Major Dialects):**

```sql
-- ANSI SQL (SQL:2016+):
SELECT
    JSON_VALUE(payload, '$.order_id')                       AS order_id,
    JSON_VALUE(payload, '$.customer.name')                  AS customer_name,
    CAST(JSON_VALUE(payload, '$.total') AS DECIMAL(10, 2))  AS order_total
FROM raw_events;

-- PostgreSQL (JSONB):
SELECT
    payload ->> 'order_id'                                  AS order_id,
    payload -> 'customer' ->> 'name'                        AS customer_name,
    CAST(payload ->> 'total' AS DECIMAL(10, 2))             AS order_total
FROM raw_events;

-- BigQuery:
SELECT
    JSON_VALUE(payload, '$.order_id')                       AS order_id,
    JSON_VALUE(payload, '$.customer.name')                  AS customer_name,
    SAFE_CAST(JSON_VALUE(payload, '$.total') AS NUMERIC)    AS order_total
FROM raw_events;

-- Snowflake (VARIANT):
SELECT
    payload:order_id::STRING                                AS order_id,
    payload:customer.name::STRING                           AS customer_name,
    TRY_CAST(payload:total::STRING AS NUMBER(10, 2))        AS order_total
FROM raw_events;
```

**2. Flattening Arrays (`UNNEST` / `FLATTEN` / `LATERAL`) & Array Filtering:**

```sql
-- PostgreSQL: LEFT JOIN LATERAL preserves parent rows with empty arrays; filter items via WHERE
SELECT
    e.payload ->> 'order_id'                         AS order_id,
    item.value ->> 'product_id'                      AS product_id,
    CAST(item.value ->> 'quantity' AS INT)           AS quantity,
    CAST(item.value ->> 'price'    AS DECIMAL(10,2)) AS unit_price
FROM raw_events e
LEFT JOIN LATERAL jsonb_array_elements(e.payload -> 'items') AS item(value) ON TRUE
WHERE CAST(item.value ->> 'price' AS DECIMAL(10,2)) >= 30.00
   OR item.value IS NULL;  -- optional: retain parent orders with empty arrays

-- BigQuery: UNNEST with LEFT JOIN + array filtering
SELECT
    JSON_VALUE(e.payload, '$.order_id')              AS order_id,
    JSON_VALUE(item, '$.product_id')                 AS product_id,
    CAST(JSON_VALUE(item, '$.price') AS NUMERIC)     AS unit_price
FROM raw_events e
LEFT JOIN UNNEST(JSON_QUERY_ARRAY(e.payload, '$.items')) AS item
WHERE CAST(JSON_VALUE(item, '$.price') AS NUMERIC) >= 30.00;

-- Snowflake: LATERAL FLATTEN with OUTER => TRUE + array filtering
SELECT
    e.payload:order_id::STRING                       AS order_id,
    f.value:product_id::STRING                       AS product_id,
    f.value:price::NUMBER(10, 2)                     AS unit_price
FROM raw_events e,
     LATERAL FLATTEN(input => e.payload:items, OUTER => TRUE) f
WHERE f.value:price::NUMBER(10, 2) >= 30.00;
```

<DialectBlock
  engine="postgres-jsonb"
  card-id="m3-pg-jsonb-lateral"
  module-id="m3"
  cloze-prompt="Recall PostgreSQL LATERAL JSONB array expansion that keeps parent rows when items is empty:"
  :cloze-prefix="'SELECT e.payload ->> \'order_id\' AS order_id, item.value ->> \'product_id\' AS product_id\nFROM raw_events e\n'"
  cloze-answer="LEFT JOIN LATERAL jsonb_array_elements(e.payload -> 'items') AS item(value) ON TRUE"
  cloze-suffix=";"
/>

### Realistic Scenario

**Context:** A Silver-layer transformation flattens raw e-commerce JSON payloads into line items, computes `line_total`, and filters to high-value line items (`unit_price >= 25.00`) while inspecting parent order metadata.

**Sample Data — `raw_events` (`payload` JSON column):**

| event_seq | payload |
|-----------|---------|
| 1 | `{"order_id": "ORD-5001", "customer": {"id": 42, "name": "Alice"}, "items": [{"product_id": "SKU-A", "quantity": 2, "price": 29.99}, {"product_id": "SKU-B", "quantity": 1, "price": 49.99}]}` |
| 2 | `{"order_id": "ORD-5002", "customer": {"id": 88, "name": "Bob"}, "items": [{"product_id": "SKU-C", "quantity": 3, "price": 10.00}, {"product_id": "SKU-D", "quantity": 1, "price": 75.00}]}` |
| 3 | `{"order_id": "ORD-5003", "customer": {"id": 91, "name": "Cara"}, "items": []}` |

**Query (PostgreSQL `JSONB` shown; see syntax box for BigQuery/Snowflake):**

```sql
SELECT
    e.payload ->> 'order_id'                           AS order_id,
    e.payload -> 'customer' ->> 'name'                 AS customer_name,
    item.value ->> 'product_id'                        AS product_id,
    CAST(item.value ->> 'quantity' AS INT)             AS quantity,
    CAST(item.value ->> 'price'    AS DECIMAL(10, 2))  AS unit_price,
    CAST(item.value ->> 'quantity' AS INT)
        * CAST(item.value ->> 'price' AS DECIMAL(10,2)) AS line_total
FROM raw_events e
CROSS JOIN LATERAL jsonb_array_elements(e.payload -> 'items') AS item(value)
WHERE CAST(item.value ->> 'price' AS DECIMAL(10, 2)) >= 25.00
ORDER BY order_id, product_id;
```

**Expected Output:**

| order_id | customer_name | product_id | quantity | unit_price | line_total |
|----------|---------------|------------|----------|------------|------------|
| ORD-5001 | Alice         | SKU-A      | 2        | 29.99      | 59.98      |
| ORD-5001 | Alice         | SKU-B      | 1        | 49.99      | 49.99      |
| ORD-5002 | Bob           | SKU-D      | 1        | 75.00      | 75.00      |

Notice that `SKU-C` (`$10.00`) and `ORD-5003` (empty `items` array) are excluded. If you needed `ORD-5003` retained with `NULL` item columns, replace `CROSS JOIN LATERAL` with `LEFT JOIN LATERAL ... ON TRUE` and move the price filter into the `JOIN ... ON` condition (or check `OR item.value IS NULL`).

> [!WARNING]
> **Gotchas & Pitfalls:**
> - **Implicit `CROSS JOIN` drops empty/null arrays:** Comma syntax (`FROM events, UNNEST(...)`) or `LATERAL FLATTEN(input => ...)` silently drops parent rows whose array is `[]` or `NULL`. Use `LEFT JOIN` / `OUTER => TRUE` whenever parent preservation matters.
> - **`WHERE` turns a `LEFT JOIN` back into an `INNER JOIN`:** Putting `WHERE item.price >= 25` after `LEFT JOIN LATERAL` drops `NULL` rows generated by empty arrays. Put item filters inside the `LEFT JOIN ... ON` clause or a pre-filtered CTE.
> - **Extracting JSON vs text (`->` vs `->>`):** In PostgreSQL, `->` returns JSON (e.g., `"Alice"` with quotes), whereas `->>` returns unquoted `TEXT`. Mixing them breaks `JOIN` conditions and `WHERE` comparisons.
> - **Untyped string comparisons:** Comparing uncast JSON strings causes lexicographical bugs (`'9.00' > '25.00'` evaluates to `TRUE`). Always `CAST` / `TRY_CAST` numeric and timestamp fields before filtering or math.

---

## 6. Idempotent Data Ingestion & Upserts

### Explanation

An **idempotent** pipeline yields the exact same target state whether executed once or retried multiple times on the same batch. Production pipelines achieve idempotency using **deduplicated `MERGE INTO` upserts** or **transactional `DELETE` + `INSERT` partition swaps**. Both strategies rely on **watermark filtering** (`WHERE _ingested_at > :high_watermark` or a lookback window on `event_time`) to process incremental slices safely without full-table scans.

### When to Use This

- Orchestrated batch pipelines (Airflow, dbt, Dagster) that automatically retry on transient warehouse failures
- Re-running historical date partitions during backfills without creating duplicate rows
- Applying incremental updates and soft-deletes (tombstones) from upstream CDC streams
- Bounding incremental ingestion costs on multi-terabyte event tables via watermarks

### Quick-Reference Syntax

**1. Deduplicated `MERGE INTO` (Upsert + Optional Delete):**

```sql
MERGE INTO dim_products AS tgt
USING (
    -- Always deduplicate source before MERGE to avoid multi-match failures
    SELECT product_id, product_name, price, updated_at, is_deleted
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY updated_at DESC) AS rn
        FROM staging_products
    ) deduped
    WHERE rn = 1
) AS src
  ON tgt.product_id = src.product_id
WHEN MATCHED AND src.is_deleted = TRUE AND src.updated_at >= tgt.updated_at THEN
    DELETE
WHEN MATCHED AND src.updated_at > tgt.updated_at THEN
    UPDATE SET
        product_name = src.product_name,
        price        = src.price,
        updated_at   = src.updated_at
WHEN NOT MATCHED AND src.is_deleted = FALSE THEN
    INSERT (product_id, product_name, price, updated_at)
    VALUES (src.product_id, src.product_name, src.price, src.updated_at);
```

**2. Transactional `DELETE` + `INSERT` (Partition Replacement):**

```sql
BEGIN TRANSACTION;

DELETE FROM fact_orders
WHERE order_date = DATE '2024-03-15';

INSERT INTO fact_orders (order_id, customer_id, amount, order_date)
SELECT order_id, customer_id, amount, order_date
FROM staging_orders
WHERE order_date = DATE '2024-03-15';

COMMIT;
```

**3. Watermark Filtering (Metadata-Backed or Lookback-Safe):**

```sql
-- Pattern A: Watermark stored in metadata table / orchestrator parameter
INSERT INTO clean_events (event_id, event_time, _ingested_at, payload)
SELECT event_id, event_time, _ingested_at, payload
FROM raw_events
WHERE _ingested_at >  :high_watermark
  AND _ingested_at <= :current_batch_watermark;

-- Pattern B: Self-referencing watermark with lookback + NOT EXISTS/MERGE safety
-- Avoids dropping late events whose event_time <= MAX(event_time)
MERGE INTO clean_events AS tgt
USING (
    SELECT event_id, event_time, payload
    FROM raw_events
    WHERE event_time > (
        SELECT COALESCE(MAX(event_time), TIMESTAMP '1970-01-01 00:00:00') - INTERVAL '1' DAY
        FROM clean_events
    )
) AS src
  ON tgt.event_id = src.event_id
WHEN NOT MATCHED THEN
    INSERT (event_id, event_time, payload)
    VALUES (src.event_id, src.event_time, src.payload);
```

### Realistic Scenario

**Context:** A daily product catalog pipeline runs `MERGE INTO` from `staging_products` into `dim_products`. Yesterday's staging table contained a stale retry for `P200`, an updated price for `P100`, a new product `P300`, and a deleted product `P400`. An upstream bug also left a duplicate row for `P100` in staging.

**Sample Data — `staging_products`:**

| product_id | product_name | price | updated_at          | is_deleted |
|------------|--------------|-------|---------------------|------------|
| P100       | Widget Pro   | 27.99 | 2024-03-15 07:00:00 | FALSE      |
| P100       | Widget Pro   | 29.99 | 2024-03-15 08:00:00 | FALSE      |
| P200       | Gadget Lite  | 12.99 | 2024-02-20 08:00:00 | FALSE      |
| P300       | Sensor Max   | 79.99 | 2024-03-15 08:00:00 | FALSE      |
| P400       | Legacy Cable | 9.99  | 2024-03-15 08:00:00 | TRUE       |

**Existing — `dim_products`:**

| product_id | product_name | price | updated_at          |
|------------|--------------|-------|---------------------|
| P100       | Widget Pro   | 24.99 | 2024-03-01 08:00:00 |
| P200       | Gadget Lite  | 14.99 | 2024-03-01 08:00:00 |
| P400       | Legacy Cable | 9.99  | 2024-03-01 08:00:00 |

**Query:** Execute the deduplicated `MERGE INTO` syntax above.

**Expected Output — `dim_products` (after `MERGE`):**

| product_id | product_name | price | updated_at          |
|------------|--------------|-------|---------------------|
| P100       | Widget Pro   | 29.99 | 2024-03-15 08:00:00 |
| P200       | Gadget Lite  | 14.99 | 2024-03-01 08:00:00 |
| P300       | Sensor Max   | 79.99 | 2024-03-15 08:00:00 |

`P100` takes only the latest deduplicated price (`29.99`), `P200` ignores the stale `2024-02-20` row because `src.updated_at > tgt.updated_at` is false, `P300` is inserted, and `P400` is deleted. Re-running this `MERGE` produces the identical table.

> [!WARNING]
> **Gotchas & Pitfalls:**
> - **Duplicate keys crash `MERGE`:** In ANSI SQL, Snowflake, BigQuery, and SQL Server, if multiple source rows match one target row, `MERGE` throws a non-deterministic cardinality error (`"Multiple rows matched"`). Always deduplicate the `USING` subquery first.
> - **Unwrapped `DELETE` + `INSERT` risks partial failure:** If `DELETE` succeeds and `INSERT` fails mid-flight without a transaction (or atomic partition overwrite), the target partition is wiped empty. Wrap in a transaction or use atomic `INSERT OVERWRITE` / `CREATE OR REPLACE`.
> - **Exclusive watermark `>` misses boundary ties:** If multiple events share the exact same `MAX(event_time)` and only half were loaded before a crash, filtering `event_time > :high_watermark` drops the remaining events at that exact timestamp. Watermark on monotonic `_ingested_at`, or use `>=` paired with deduplication/`MERGE`.
> - **Late data skipped by `event_time` watermarks:** Using `WHERE event_time > (SELECT MAX(event_time) FROM target)` permanently drops late-arriving records with older event timestamps. Watermark on ingestion arrival time (`_ingested_at`) or apply a lookback buffer.

---

## 7. Date, Time & Calendar Spines

### Explanation

A **calendar spine** (date dimension or generated series) provides one unbroken row per date or hour so `LEFT JOIN` queries emit zero-filled buckets instead of dropping quiet periods. Production pipelines store raw timestamps strictly in **UTC**, convert to IANA timezones only at presentation or business-day aggregation boundaries, and use standardized date arithmetic (`DATE_TRUNC`, `INTERVAL`) for period rollups.

### When to Use This

- Filling zero-activity gaps in daily/hourly dashboards, rolling averages, or retention charts
- Converting UTC event logs into local business dates (e.g., store closing dates in `America/New_York`)
- Building reusable `dim_date` tables with weekends, fiscal calendars, and month-end flags
- Computing period-over-period comparisons, billing cycles, or SLA durations

### Quick-Reference Syntax

**1. Generating a Calendar Spine (`GENERATE_SERIES` vs ANSI Recursive CTE):**

```sql
-- ANSI SQL (Recursive CTE — works across PostgreSQL, Snowflake, DuckDB, SQLite, SQL Server)
WITH RECURSIVE date_spine AS (
    SELECT DATE '2024-03-01' AS dt
    UNION ALL
    SELECT CAST(dt + INTERVAL '1' DAY AS DATE)
    FROM date_spine
    WHERE dt < DATE '2024-03-31'
)
SELECT dt FROM date_spine;

-- PostgreSQL native (fast, no recursion cap):
SELECT gs::DATE AS dt
FROM generate_series(DATE '2024-03-01', DATE '2024-03-31', INTERVAL '1 day') AS gs;

-- BigQuery:  SELECT dt FROM UNNEST(GENERATE_DATE_ARRAY('2024-03-01', '2024-03-31')) AS dt;
-- Snowflake: SELECT DATEADD('day', SEQ4(), '2024-03-01'::DATE) AS dt FROM TABLE(GENERATOR(ROWCOUNT => 31));
```

**2. Timezone Conversions (UTC to Local Business Date) & Date Arithmetic:**

```sql
-- PostgreSQL: Distinguish timezone-aware (TIMESTAMPTZ) vs naive (TIMESTAMP)
SELECT
    event_id,
    event_ts_utc,                                              -- TIMESTAMPTZ (aware)
    event_ts_utc AT TIME ZONE 'America/New_York' AS local_ts,  -- converts aware UTC -> local NY wall time
    DATE(event_ts_utc AT TIME ZONE 'America/New_York') AS ny_business_date,
    -- If stored as naive TIMESTAMP (no tz), tag it UTC first:
    (naive_utc_ts AT TIME ZONE 'UTC') AT TIME ZONE 'America/New_York' AS safe_local_ts
FROM events;

-- BigQuery:  DATETIME(event_ts_utc, 'America/New_York')
-- Snowflake: CONVERT_TIMEZONE('UTC', 'America/New_York', naive_utc_ts)

-- Common ANSI / Warehouse Date Arithmetic:
SELECT
    DATE_TRUNC('month', DATE '2024-03-15')                             AS month_start,
    DATE_TRUNC('month', DATE '2024-03-15') + INTERVAL '1' MONTH
                                           - INTERVAL '1' DAY          AS month_end,
    DATE '2024-03-15' - INTERVAL '7' DAY                               AS seven_days_ago;
```

### Realistic Scenario 1 — Filling Zero-Activity Days with a Calendar Spine

**Context:** Finance requires a daily revenue report for `2024-03-01` through `2024-03-05`. Raw orders have no rows on March 2 or March 4, which would disappear under a plain `GROUP BY`.

**Sample Data — `orders`:**

| order_id | order_ts_utc        | amount |
|----------|---------------------|--------|
| 1        | 2024-03-01 14:00:00 | 150.00 |
| 2        | 2024-03-01 22:30:00 | 75.00  |
| 3        | 2024-03-03 16:00:00 | 200.00 |
| 4        | 2024-03-05 03:30:00 | 50.00  |

*(Note: `order_id = 4` occurred at `2024-03-05 03:30:00 UTC`, which is `2024-03-04 22:30:00 EST` in `America/New_York`!)*

**Query (UTC Spine + Local Business Date Join):**

```sql
WITH RECURSIVE date_spine AS (
    SELECT DATE '2024-03-01' AS dt
    UNION ALL
    SELECT CAST(dt + INTERVAL '1' DAY AS DATE)
    FROM date_spine
    WHERE dt < DATE '2024-03-05'
),
orders_ny AS (
    SELECT
        order_id,
        amount,
        DATE((order_ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'America/New_York') AS ny_date
    FROM orders
)
SELECT
    ds.dt                      AS report_date_ny,
    COALESCE(SUM(o.amount), 0) AS daily_revenue,
    COUNT(o.order_id)          AS order_count
FROM date_spine ds
LEFT JOIN orders_ny o
    ON ds.dt = o.ny_date
GROUP BY ds.dt
ORDER BY ds.dt;
```

**Expected Output:**

| report_date_ny | daily_revenue | order_count |
|----------------|---------------|-------------|
| 2024-03-01     | 225.00        | 2           |
| 2024-03-02     | 0.00          | 0           |
| 2024-03-03     | 200.00        | 1           |
| 2024-03-04     | 50.00         | 1           |
| 2024-03-05     | 0.00          | 0           |

Converting UTC to `America/New_York` before joining onto the spine places order `4` on its true NY business date (`2024-03-04`), while `LEFT JOIN` + `COALESCE` ensures March 2 and March 5 still appear with `0.00`.

### Realistic Scenario 2 — Timezone Conversion Across Daylight Saving Time (DST)

**Context:** On `2024-03-10`, US Eastern Time sprang forward at `02:00 EST` (`07:00 UTC`) from `UTC-5` to `UTC-4`. Hardcoding a fixed `-5 hours` offset would miscalculate every timestamp after `07:00 UTC`.

**Sample Data — `dst_events` (`event_ts_utc` stored as `TIMESTAMPTZ` in UTC):**

| event_id | event_ts_utc             |
|----------|--------------------------|
| E1       | 2024-03-10 04:00:00+00   |
| E2       | 2024-03-10 06:30:00+00   |
| E3       | 2024-03-10 07:30:00+00   |

**Query:**

```sql
SELECT
    event_id,
    event_ts_utc,
    event_ts_utc AT TIME ZONE 'America/New_York'       AS local_time_ny,
    DATE(event_ts_utc AT TIME ZONE 'America/New_York') AS local_date_ny
FROM dst_events
ORDER BY event_id;
```

**Expected Output:**

| event_id | event_ts_utc           | local_time_ny       | local_date_ny |
|----------|------------------------|---------------------|---------------|
| E1       | 2024-03-10 04:00:00+00 | 2024-03-09 23:00:00 | 2024-03-09    |
| E2       | 2024-03-10 06:30:00+00 | 2024-03-10 01:30:00 | 2024-03-10    |
| E3       | 2024-03-10 07:30:00+00 | 2024-03-10 03:30:00 | 2024-03-10    |

> [!WARNING]
> **Gotchas & Pitfalls:**
> - **Fixed abbreviations ignore DST:** `AT TIME ZONE 'EST'` pins a constant `-05:00` offset year-round. Always use full IANA timezone names like `'America/New_York'` or `'Europe/London'` so DST shifts happen automatically.
> - **Postgres `AT TIME ZONE` flips behavior on naive timestamps:** Calling `naive_ts AT TIME ZONE 'America/New_York'` tells Postgres the naive timestamp is *already* in New York time and converts it *to* UTC! Double-check column types or explicitly tag naive UTC timestamps first: `(ts AT TIME ZONE 'UTC') AT TIME ZONE 'America/New_York'`.
> - **Joining a `DATE` spine directly to a `TIMESTAMP`:** `spine.dt = orders.created_at` only matches midnight (`00:00:00`) rows. Cast/extract the date (`DATE(orders.created_at) = spine.dt`) or use a half-open range join (`created_at >= spine.dt AND created_at < spine.dt + INTERVAL '1' DAY`) to preserve index/partition pruning!
> - **Filtering a `LEFT JOIN` table in `WHERE`:** Writing `LEFT JOIN orders o ... WHERE o.status = 'completed'` destroys the zero-filled spine rows because `NULL = 'completed'` is falsy. Put fact-table filters inside the `LEFT JOIN ... ON` clause or a pre-filtered CTE.
> - **Month-end arithmetic & recursion caps:** `DATE '2024-01-31' + INTERVAL '1' MONTH` clamps to `2024-02-29` in PostgreSQL/Snowflake, errors in some engines, and recursive CTEs often cap at 100–1,000 rows (`MAXRECURSION` in SQL Server). Prefer a materialized `dim_date` table for multi-year ranges.

---

## Quick Reference: Pattern Selection Guide

| Problem | Pattern | Key SQL Feature |
|---------|---------|-----------------|
| Duplicate rows from replay/retry | [Deduplication](#1-deduplication) | `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)` |
| Track dimension history | [SCD Type 2](#2-change-data-capture-cdc--slowly-changing-dimensions-scd) | `valid_from` / `valid_to` / `is_current` + `LEAD()` |
| Overwrite dimension (no history) | [SCD Type 1](#2-change-data-capture-cdc--slowly-changing-dimensions-scd) | `MERGE ... WHEN MATCHED THEN UPDATE` |
| Find consecutive login streaks | [Gaps & Islands](#3-gaps--islands) | `activity_date - (ROW_NUMBER() * INTERVAL '1' DAY)` |
| Group contiguous status ranges | [Gaps & Islands](#3-gaps--islands) | Double `ROW_NUMBER()` difference + `GROUP BY status` |
| Group events into sessions | [Sessionization](#4-sessionization) | `LAG()` + cumulative `SUM()` with `ROWS UNBOUNDED PRECEDING` |
| Parse & filter JSON arrays | [Semi-Structured Data](#5-semi-structured-data-json) | `JSON_VALUE`, `UNNEST` / `LATERAL FLATTEN` + `LEFT JOIN` |
| Safe re-runnable incremental loads | [Idempotent Ingestion](#6-idempotent-data-ingestion--upserts) | Deduplicated `MERGE INTO`, transactional `DELETE`+`INSERT` |
| Fill zero-activity time gaps | [Calendar Spines](#7-date-time--calendar-spines) | Recursive CTE / `GENERATE_SERIES` + `LEFT JOIN` |
| Convert UTC to local business date | [Date & Time](#7-date-time--calendar-spines) | `AT TIME ZONE 'IANA/Name'` before `DATE()` truncation |
