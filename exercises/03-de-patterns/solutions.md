# Module 3 Solutions: Production Data Engineering Patterns

> Complete solutions, expected outputs, and architectural explanations for [Module 3 Quiz](./quiz.md).

---

## Question 1 — Deduplication: Non-Deterministic Ties & `RANK()` Trap

**Correct Answer:** **B**

### Explanation

- `RANK()` assigns `1` to both tied rows when `updated_at` values are equal, so `WHERE rnk = 1` keeps duplicates instead of collapsing them. `ROW_NUMBER()` guarantees at most one row per partition receives `1`.
- Adding `_ingested_at DESC` (and `_kafka_offset DESC` if available) makes the tie-breaker **deterministic** so re-running a backfill always selects the same winning record.
- **Why other options fail:**
  - **A:** `DENSE_RANK()` still gives `1` to both tied rows, and `SELECT DISTINCT` won't collapse them if `_ingested_at` (or any payload column) differs.
  - **C:** Adding `_ingested_at` to `PARTITION BY` creates separate partitions for every ingestion timestamp, emitting *more* duplicates instead of fewer.
  - **D:** `LIMIT 1` truncates the entire table to 1 row globally instead of 1 row per `order_id`.

---

## Question 2 — Deduplication: Handling Late-Arriving Data

### Solution

```sql
WITH ranked AS (
    SELECT
        payment_id,
        order_id,
        status,
        updated_at,
        _ingested_at,
        ROW_NUMBER() OVER (
            PARTITION BY payment_id
            ORDER BY updated_at DESC NULLS LAST, _ingested_at DESC
        ) AS rn
    FROM raw_payments
    WHERE _ingested_at >= TIMESTAMP '2024-04-09 00:00:00'
)
SELECT
    payment_id,
    order_id,
    status,
    updated_at,
    _ingested_at
FROM ranked
WHERE rn = 1
ORDER BY payment_id;
```

### Expected Output

| payment_id | order_id | status  | updated_at          | _ingested_at        |
|------------|----------|---------|---------------------|---------------------|
| P-101      | 501      | settled | 2024-04-09 23:55:00 | 2024-04-10 02:15:00 |
| P-102      | 502      | settled | 2024-04-10 08:00:00 | 2024-04-10 08:30:00 |

### Explanation

1. **Filtering by `_ingested_at` (not `updated_at`):** If we filtered `updated_at >= '2024-04-10'`, the late settlement for `P-101` (whose `updated_at` is `2024-04-09 23:55:00` but landed at `2024-04-10 02:15:00`) would be missed. Filtering `_ingested_at >= TIMESTAMP '2024-04-09 00:00:00'` catches both yesterday's records and today's late arrivals while excluding old history (`P-103`).
2. **Deterministic tie-breaking:** `P-102` has identical `updated_at` timestamps; `_ingested_at DESC` deterministically chooses the `08:30:00` row.

---

## Question 3 — SCD Type 2: Point-in-Time Join Fan-Out & `NULL` Traps

**Correct Answer:** **A**

### Explanation

- **Half-open intervals (`>= valid_from AND < valid_to`):** `BETWEEN` is inclusive on both ends (`>= valid_from AND <= valid_to`). When an invoice falls on the exact date a dimension version rolled over (`valid_to` of v1 = `valid_from` of v2), `BETWEEN` matches **both** rows and doubles the invoice revenue! Half-open `[valid_from, valid_to)` ensures every date matches at most one version.
- **`IS DISTINCT FROM` for `NULL`-safe comparison:** In three-valued SQL logic, `NULL <> 'enterprise'` evaluates to `UNKNOWN` (falsy in `WHERE`), silently skipping `NULL` → non-`NULL` updates. `IS DISTINCT FROM` treats `NULL` as a distinct comparable value (`NULL IS DISTINCT FROM 'enterprise'` → `TRUE`).
- **Why other options fail:** **B** shifts the overlap risk onto `valid_to` vs next `valid_from` if the open sentinel isn't exclusive or misses the initial `valid_from` date; **C** drops historical versions by locking to `is_current = TRUE`; **D** still breaks on `NULL`s and `DISTINCT f.invoice_id` cannot repair downstream `SUM(f.amount)` fan-out cleanly if multiple rows appear.

---

## Question 4 — CDC & SCD Type 2: Out-of-Order Timeline Reconstruction

### Solution

```sql
WITH deduped_cdc AS (
    SELECT
        account_id,
        plan_tier,
        effective_date,
        ROW_NUMBER() OVER (
            PARTITION BY account_id, effective_date
            ORDER BY _ingested_at DESC
        ) AS rn
    FROM cdc_subscription_events
),
with_prev AS (
    SELECT
        account_id,
        plan_tier,
        effective_date,
        LAG(plan_tier) OVER (
            PARTITION BY account_id
            ORDER BY effective_date
        ) AS prev_plan_tier
    FROM deduped_cdc
    WHERE rn = 1
),
true_changes AS (
    SELECT
        account_id,
        plan_tier,
        effective_date
    FROM with_prev
    WHERE plan_tier IS DISTINCT FROM prev_plan_tier
)
SELECT
    account_id,
    plan_tier,
    effective_date AS valid_from,
    COALESCE(
        LEAD(effective_date) OVER (
            PARTITION BY account_id
            ORDER BY effective_date
        ),
        DATE '9999-12-31'
    ) AS valid_to,
    CASE
        WHEN LEAD(effective_date) OVER (
            PARTITION BY account_id
            ORDER BY effective_date
        ) IS NULL THEN TRUE
        ELSE FALSE
    END AS is_current
FROM true_changes
ORDER BY account_id, valid_from;
```

### Expected Output

| account_id | plan_tier  | valid_from | valid_to   | is_current |
|------------|------------|------------|------------|------------|
| A-10       | free       | 2024-01-01 | 2024-03-01 | FALSE      |
| A-10       | pro        | 2024-03-01 | 2024-05-01 | FALSE      |
| A-10       | enterprise | 2024-05-01 | 9999-12-31 | TRUE       |
| A-20       | starter    | 2024-02-01 | 9999-12-31 | TRUE       |

### Explanation

1. `deduped_cdc` handles multiple CDC events arriving for the same `(account_id, effective_date)`.
2. `with_prev` + `true_changes` uses `LAG(plan_tier)` and `IS DISTINCT FROM` to discard consecutive no-op snapshots (`A-20` on `2024-04-01` stays `starter`, so it is collapsed). Notice that if `A-20` later changed back (`starter -> pro -> starter`), `LAG()` still preserves the transition because it only compares adjacent chronological states.
3. Sorting by `effective_date` (not `_ingested_at`) and taking `LEAD(effective_date)` stitches `A-10`'s late `2024-03-01` `pro` record cleanly between `free` and `enterprise`.

---

## Question 5 — Gaps & Islands: Longest Consecutive Active Streak

### Solution

```sql
WITH distinct_days AS (
    SELECT DISTINCT
        user_id,
        CAST(login_ts AS DATE) AS login_date
    FROM user_activity
),
numbered AS (
    SELECT
        user_id,
        login_date,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY login_date
        ) AS rn
    FROM distinct_days
),
islands AS (
    SELECT
        user_id,
        login_date,
        login_date - (rn * INTERVAL '1' DAY) AS island_id
    FROM numbered
),
streaks AS (
    SELECT
        user_id,
        MIN(login_date) AS streak_start,
        MAX(login_date) AS streak_end,
        COUNT(*)        AS streak_days
    FROM islands
    GROUP BY user_id, island_id
),
ranked_streaks AS (
    SELECT
        user_id,
        streak_start,
        streak_end,
        streak_days AS longest_streak_days,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY streak_days DESC, streak_end DESC
        ) AS streak_rank
    FROM streaks
)
SELECT
    user_id,
    streak_start,
    streak_end,
    longest_streak_days
FROM ranked_streaks
WHERE streak_rank = 1
ORDER BY user_id;
```

*(Dialect note: Replace `login_date - (rn * INTERVAL '1' DAY)` with `DATE_SUB(login_date, INTERVAL rn DAY)` in BigQuery or `DATEADD('day', -rn, login_date)` in Snowflake.)*

### Expected Output

| user_id | streak_start | streak_end | longest_streak_days |
|---------|--------------|------------|---------------------|
| U1      | 2024-05-01   | 2024-05-03 | 3                   |
| U2      | 2024-05-04   | 2024-05-06 | 3                   |

### Explanation

- **Critical first step (`distinct_days`):** `U1` has two logins on `2024-05-01`. Truncating `login_ts` to `DATE` and taking `DISTINCT` prevents `ROW_NUMBER()` from advancing twice on the same day and breaking the streak.
- **Tie-breaker on `ranked_streaks`:** Adding `streak_end DESC` ensures deterministic selection if a user has two streaks tied for the longest length (picking the most recent).

---

## Question 6 — Gaps & Islands: Grouping Contiguous Server Status Ranges

### Solution

**Approach A — Double `ROW_NUMBER()` Difference:**

```sql
WITH status_groups AS (
    SELECT
        server_id,
        status,
        ping_ts,
        ROW_NUMBER() OVER (PARTITION BY server_id ORDER BY ping_ts, ping_id)
      - ROW_NUMBER() OVER (PARTITION BY server_id, status ORDER BY ping_ts, ping_id) AS grp
    FROM server_pings
)
SELECT
    server_id,
    status,
    MIN(ping_ts) AS period_start,
    MAX(ping_ts) AS period_end,
    COUNT(*)     AS ping_count
FROM status_groups
GROUP BY server_id, status, grp
ORDER BY server_id, period_start;
```

**Approach B — Single-Pass `LAG()` + Cumulative `SUM()` (Alternative):**

```sql
WITH with_prev AS (
    SELECT
        server_id,
        ping_id,
        ping_ts,
        status,
        LAG(status) OVER (PARTITION BY server_id ORDER BY ping_ts, ping_id) AS prev_status
    FROM server_pings
),
flagged AS (
    SELECT
        server_id,
        ping_id,
        ping_ts,
        status,
        CASE WHEN status IS DISTINCT FROM prev_status THEN 1 ELSE 0 END AS is_change
    FROM with_prev
),
grouped AS (
    SELECT
        *,
        SUM(is_change) OVER (
            PARTITION BY server_id
            ORDER BY ping_ts, ping_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS grp
    FROM flagged
)
SELECT
    server_id,
    status,
    MIN(ping_ts) AS period_start,
    MAX(ping_ts) AS period_end,
    COUNT(*)     AS ping_count
FROM grouped
GROUP BY server_id, status, grp
ORDER BY server_id, period_start;
```

### Expected Output

| server_id | status   | period_start        | period_end          | ping_count |
|-----------|----------|---------------------|---------------------|------------|
| api-1     | HEALTHY  | 2024-05-01 00:00:00 | 2024-05-01 00:01:00 | 2          |
| api-1     | DEGRADED | 2024-05-01 00:02:00 | 2024-05-01 00:02:00 | 1          |
| api-1     | HEALTHY  | 2024-05-01 00:03:00 | 2024-05-01 00:04:00 | 2          |

### Explanation

- In **Approach A**, `rn_all - rn_status` remains constant within a contiguous run of a status (`0` for the first `HEALTHY` block, `1` for the second `HEALTHY` block) because `rn_all` jumps forward by `1` during the `DEGRADED` row while `rn_HEALTHY` pauses. Notice that `DEGRADED` gets `grp = 2` and the second `HEALTHY` block gets `grp = 1`; including `status` in `GROUP BY` prevents different statuses from ever colliding even if their `grp` integers match.
- Including `ping_id` in `ORDER BY ping_ts, ping_id` guarantees deterministic behavior if two pings ever land on the same timestamp.

---

## Question 7 — Sessionization: 30-Minute Clickstream Sessions

### Solution

```sql
WITH lagged AS (
    SELECT
        user_id,
        event_id,
        event_ts,
        LAG(event_ts) OVER (
            PARTITION BY user_id
            ORDER BY event_ts, event_id
        ) AS prev_event_ts
    FROM web_events
),
flagged AS (
    SELECT
        user_id,
        event_id,
        event_ts,
        CASE
            WHEN prev_event_ts IS NULL THEN 1
            WHEN event_ts - prev_event_ts > INTERVAL '30' MINUTE THEN 1
            ELSE 0
        END AS is_new_session
    FROM lagged
),
sessionized AS (
    SELECT
        user_id,
        event_id,
        event_ts,
        SUM(is_new_session) OVER (
            PARTITION BY user_id
            ORDER BY event_ts, event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS session_seq
    FROM flagged
)
SELECT
    user_id,
    user_id || '-' || CAST(session_seq AS VARCHAR(20)) AS global_session_id,
    MIN(event_ts) AS session_start,
    MAX(event_ts) AS session_end,
    COUNT(*)      AS event_count
FROM sessionized
GROUP BY user_id, session_seq
ORDER BY user_id, session_start;
```

### Expected Output

| user_id | global_session_id | session_start       | session_end         | event_count |
|---------|-------------------|---------------------|---------------------|-------------|
| u1      | u1-1              | 2024-05-01 10:00:00 | 2024-05-01 10:45:00 | 3           |
| u1      | u1-2              | 2024-05-01 11:16:00 | 2024-05-01 11:16:00 | 1           |
| u2      | u2-1              | 2024-05-01 10:05:00 | 2024-05-01 10:05:00 | 2           |

### Explanation

- `e2` (`10:15`) → `e3` (`10:45`) is **exactly** 30 minutes, so `> INTERVAL '30' MINUTE` evaluates to `FALSE` and keeps `e3` in `u1-1`.
- `e3` (`10:45`) → `e4` (`11:16`) is 31 minutes, triggering `is_new_session = 1` and starting `u1-2`.
- `u2` has two events with identical timestamps (`10:05:00`); adding `event_id` to `ORDER BY` and specifying `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` avoids default `RANGE` frame peer-grouping surprises.

---

## Question 8 — Sessionization: Boundary & `DATEDIFF` Pitfalls

**Correct Answer:** **D**

### Explanation

1. **How `DATEDIFF('minute', ...)` works:** In Snowflake and SQL Server, `DATEDIFF('minute', t1, t2)` counts **minute boundary crossings**, not full 60-second intervals! Going from `10:00:59` to `10:31:01` crosses `31` minute boundaries (`10:01` through `10:31`), returning `31` (`> 30`). Conversely, `10:00:01` to `10:30:59` (30 minutes 58 seconds!) returns **`30`**, silently *failing* to split! To measure exact elapsed inactivity, always compare seconds (`DATEDIFF('second', prev_event_ts, event_ts) > 1800`) or native intervals (`> INTERVAL '30' MINUTE`).
2. **Midnight batch splitting:** Filtering strictly to `WHERE DATE(event_ts) = :run_date` cuts off `23:50` from `00:10` across two independent daily runs, resetting `LAG()` at midnight and splitting one continuous session into two. Fix this by reading a lookback overlap window (at least the session timeout, or an active-session state table) and merging boundaries.

---

## Question 9 — Semi-Structured Data: Flattening Arrays Without Dropping Empty Parents

### Solution (PostgreSQL `JSONB`, BigQuery & Snowflake equivalents shown)

**PostgreSQL (`JSONB`) — `LEFT JOIN LATERAL` with filter inside `ON`:**

```sql
SELECT
    e.payload ->> 'order_id'                         AS order_id,
    item.value ->> 'sku'                             AS sku,
    CAST(item.value ->> 'qty'   AS INT)              AS qty,
    CAST(item.value ->> 'price' AS DECIMAL(10, 2))   AS price,
    CAST(item.value ->> 'qty'   AS INT)
        * CAST(item.value ->> 'price' AS DECIMAL(10, 2)) AS line_total
FROM raw_api_orders e
LEFT JOIN LATERAL jsonb_array_elements(e.payload -> 'items') AS item(value)
    ON CAST(item.value ->> 'price' AS DECIMAL(10, 2)) >= 20.00
ORDER BY order_id, sku;
```

**Universal CTE Pattern (works across PostgreSQL, BigQuery, and Snowflake):**

```sql
-- Example shown in Snowflake syntax (for BigQuery use UNNEST + JSON_VALUE):
WITH filtered_items AS (
    SELECT
        e.id,
        f.value:sku::STRING             AS sku,
        f.value:qty::INT                AS qty,
        f.value:price::NUMBER(10, 2)    AS price
    FROM raw_api_orders e,
         LATERAL FLATTEN(input => e.payload:items) f
    WHERE f.value:price::NUMBER(10, 2) >= 20.00
)
SELECT
    e.payload:order_id::STRING AS order_id,
    fi.sku,
    fi.qty,
    fi.price,
    fi.qty * fi.price          AS line_total
FROM raw_api_orders e
LEFT JOIN filtered_items fi
  ON e.id = fi.id
ORDER BY order_id, fi.sku;
```

### Expected Output

| order_id | sku  | qty  | price | line_total |
|----------|------|------|-------|------------|
| O-10     | S1   | 2    | 25.00 | 50.00      |
| O-11     | NULL | NULL | NULL  | NULL       |
| O-12     | NULL | NULL | NULL  | NULL       |

### Explanation

- Using `CROSS JOIN` (or comma syntax) drops `O-11` immediately because `items: []` yields 0 rows.
- Using `LEFT JOIN` with `WHERE price >= 20.00` in the outer `WHERE` clause *also* drops `O-11` and `O-12`, because `NULL >= 20.00` is `UNKNOWN` and `5.00 >= 20.00` is `FALSE`—converting the `LEFT JOIN` back into an `INNER JOIN`!
- Placing the price predicate inside the `LEFT JOIN ... ON` clause (or pre-filtering items in a CTE before `LEFT JOIN`) retains both `O-11` and `O-12` with `NULL` item columns.

---

## Question 10 — Idempotent Ingestion: `MERGE INTO` & Watermark Pitfalls

**Correct Answer:** **B**

### Explanation

1. **Fixing the `MERGE` crash:** When two rows in the `USING` subquery share the same `event_id`, `MERGE` cannot decide which update to apply and fails with a duplicate-match error. Deduplicating `raw_events` with `ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY event_time DESC, _ingested_at DESC)` inside `USING` guarantees a `<= 1:1` match per target key.
2. **Fixing dropped late-arriving data:** Filtering `WHERE event_time > (SELECT MAX(event_time) FROM clean_events)` permanently skips any late event whose `event_time` is older than the high-water mark already in `clean_events`. Filtering on the monotonic arrival timestamp (`_ingested_at > :high_watermark`) or scanning a safe lookback buffer (`event_time >= MAX(event_time) - INTERVAL '...'`) paired with `MERGE` ensures late arrivals are picked up idempotently.

---

## Question 11 — Idempotent Ingestion: Deduplicated `MERGE INTO` with Soft Deletes

### Solution

```sql
MERGE INTO dim_inventory AS tgt
USING (
    SELECT
        sku,
        stock_qty,
        updated_at,
        is_deleted
    FROM (
        SELECT
            sku,
            stock_qty,
            updated_at,
            is_deleted,
            ROW_NUMBER() OVER (
                PARTITION BY sku
                ORDER BY updated_at DESC
            ) AS rn
        FROM stg_inventory
    ) deduped
    WHERE rn = 1
) AS src
  ON tgt.sku = src.sku
WHEN MATCHED AND src.is_deleted = TRUE AND src.updated_at >= tgt.updated_at THEN
    DELETE
WHEN MATCHED AND src.is_deleted = FALSE AND src.updated_at > tgt.updated_at THEN
    UPDATE SET
        stock_qty  = src.stock_qty,
        updated_at = src.updated_at
WHEN NOT MATCHED AND src.is_deleted = FALSE THEN
    INSERT (sku, stock_qty, updated_at)
    VALUES (src.sku, src.stock_qty, src.updated_at);
```

### Resulting `dim_inventory` Table

| sku  | stock_qty | updated_at          |
|------|-----------|---------------------|
| SK-1 | 18        | 2024-05-02 09:00:00 |
| SK-2 | 50        | 2024-05-01 08:00:00 |
| SK-4 | 40        | 2024-05-02 09:00:00 |

### Explanation

- `SK-1` is deduplicated in `USING` first (`18` at `09:00:00` wins), preventing a multi-match `MERGE` crash.
- `SK-2` stays `50` because the incoming `2024-04-28` record fails `src.updated_at > tgt.updated_at`.
- `SK-3` matches the `DELETE` branch (`is_deleted = TRUE` and newer timestamp).
- `SK-4` inserts normally, while `SK-5` is skipped because `src.is_deleted = FALSE` guards the `INSERT` branch against inserting unknown tombstones.

---

## Question 12 — Calendar Spines, Timezones & DST

### Solution

```sql
WITH RECURSIVE date_spine AS (
    SELECT DATE '2024-03-09' AS report_date_ny
    UNION ALL
    SELECT CAST(report_date_ny + INTERVAL '1' DAY AS DATE)
    FROM date_spine
    WHERE report_date_ny < DATE '2024-03-12'
),
paid_orders_ny AS (
    SELECT
        order_id,
        amount,
        DATE(order_ts_utc AT TIME ZONE 'America/New_York') AS order_date_ny
    FROM orders
    WHERE status = 'paid'
)
SELECT
    ds.report_date_ny,
    COALESCE(SUM(o.amount), 0.00) AS paid_revenue,
    COUNT(o.order_id)             AS paid_orders
FROM date_spine ds
LEFT JOIN paid_orders_ny o
    ON ds.report_date_ny = o.order_date_ny
GROUP BY ds.report_date_ny
ORDER BY ds.report_date_ny;
```

*(Note: If `order_ts_utc` were a timezone-naive `TIMESTAMP` storing UTC instead of `TIMESTAMPTZ`, use `DATE((order_ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'America/New_York')` in PostgreSQL, `DATE(DATETIME(order_ts_utc, 'America/New_York'))` in BigQuery, or `DATE(CONVERT_TIMEZONE('UTC', 'America/New_York', order_ts_utc))` in Snowflake.)*

### Expected Output

| report_date_ny | paid_revenue | paid_orders |
|----------------|--------------|-------------|
| 2024-03-09     | 100.00       | 1           |
| 2024-03-10     | 50.00        | 1           |
| 2024-03-11     | 40.00        | 1           |
| 2024-03-12     | 0.00         | 0           |

### Explanation

- **Order `101` (`2024-03-10 04:30:00+00`):** Before the `07:00 UTC` DST switch (`UTC-5`), this converts to `2024-03-09 23:30:00 EST` → **`2024-03-09`**.
- **Order `102` (`2024-03-10 07:30:00+00`):** After the `07:00 UTC` DST switch (`UTC-4`), this converts to `2024-03-10 03:30:00 EDT` → **`2024-03-10`**.
- **Order `103`:** Excluded inside `paid_orders_ny` because `status = 'cancelled'`.
- **Order `104` (`2024-03-11 04:30:00+00`):** Under DST (`UTC-4`), this converts to `2024-03-11 00:30:00 EDT` → **`2024-03-11`** (whereas a buggy hardcoded `'EST'` offset would have placed it on `2024-03-10 23:30:00`!).
- **`2024-03-12` preserved as `0.00`:** Filtering `WHERE status = 'paid'` inside the `paid_orders_ny` CTE (rather than in an outer `WHERE` after `LEFT JOIN`) ensures `2024-03-12` survives with `0.00` revenue and `0` orders.
