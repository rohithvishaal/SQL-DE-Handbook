# Module 3 Quiz: Production Data Engineering Patterns

> Test your mastery of production SQL patterns covered in [Module 3](../../cheatsheets/03-de-patterns.md). Each question is based on a real-world Data Engineering failure mode, pipeline design decision, or interview scenario.
>
> Use the **Explanation** / **Solution & Explanation** tab on each card after attempting the question!

---

## Question 1 — Deduplication: Non-Deterministic Ties & `RANK()` Trap *(Multiple Choice)*

An on-call engineer investigates duplicate rows in `silver_orders`, which is populated nightly using the query below from an at-least-once Kafka staging table `raw_orders`:

```sql
WITH ranked AS (
    SELECT
        order_id,
        status,
        updated_at,
        _ingested_at,
        RANK() OVER (
            PARTITION BY order_id
            ORDER BY updated_at DESC
        ) AS rnk
    FROM raw_orders
)
SELECT order_id, status, updated_at
FROM ranked
WHERE rnk = 1;
```

Yesterday, two messages for `order_id = 8812` landed with identical `updated_at = '2024-05-01 12:00:00'` (`_ingested_at = '12:01:00'` vs `'12:05:00'`), and both rows appeared in `silver_orders`. Even after switching `RANK()` to `ROW_NUMBER()`, results flip unpredictably on backfill re-runs.

What fixes **both** the duplicate output and the non-deterministic backfill behavior?

- **A.** Replace `RANK()` with `DENSE_RANK()` and add `DISTINCT` in the outer `SELECT`.
- **B.** Replace `RANK()` with `ROW_NUMBER()` and add `_ingested_at DESC` (and/or `_kafka_offset DESC`) as secondary sort keys in `ORDER BY`.
- **C.** Replace `RANK()` with `ROW_NUMBER()` and add `_ingested_at` to `PARTITION BY order_id, _ingested_at`.
- **D.** Keep `RANK()` and add `LIMIT 1` to the outer query.

---

## Question 2 — Deduplication: Handling Late-Arriving Data *(Write the Query)*

Your daily payment pipeline runs for `2024-04-10`, reading from `raw_payments`. Late-arriving settlement updates frequently land up to 2 days after the original transaction timestamp. Because `raw_payments` is append-only, you want to process everything ingested on or after `2024-04-09 00:00:00` (2-day ingestion lookback) and keep only the single latest version per `payment_id` with deterministic tie-breaking.

**Sample Data — `raw_payments`:**

| payment_id | order_id | status   | updated_at          | _ingested_at        |
|------------|----------|----------|---------------------|---------------------|
| P-101      | 501      | pending  | 2024-04-09 23:40:00 | 2024-04-09 23:41:00 |
| P-101      | 501      | settled  | 2024-04-09 23:55:00 | 2024-04-10 02:15:00 |
| P-102      | 502      | settled  | 2024-04-10 08:00:00 | 2024-04-10 08:01:00 |
| P-102      | 502      | settled  | 2024-04-10 08:00:00 | 2024-04-10 08:30:00 |
| P-103      | 503      | refunded | 2024-04-05 12:00:00 | 2024-04-05 12:02:00 |

**Task:** Write an ANSI SQL query returning `(payment_id, order_id, status, updated_at, _ingested_at)` for the lookback window (`_ingested_at >= TIMESTAMP '2024-04-09 00:00:00'`), deduplicated to 1 row per `payment_id`.

---

## Question 3 — SCD Type 2: Point-in-Time Join Fan-Out & `NULL` Traps *(Multiple Choice)*

A finance analyst runs an "as-of" revenue report joining `fact_invoices` (`invoice_date`) to an SCD Type 2 table `dim_customer` (`valid_from`, `valid_to`, `is_current`), where `dim_customer` uses contiguous half-open boundaries (`valid_to` of row 1 equals `valid_from` of row 2):

```sql
SELECT
    f.invoice_id,
    f.amount,
    d.tier
FROM fact_invoices f
JOIN dim_customer d
  ON f.customer_id = d.customer_id
 AND f.invoice_date BETWEEN d.valid_from AND d.valid_to;
```

After deploying, total revenue doubles for customers who upgraded plans on the exact day an invoice was issued. Additionally, when a customer's `tier` changes from `NULL` to `'enterprise'`, the ETL job (`WHERE d.tier <> src.tier`) fails to record a new SCD2 version.

Which combination correctly fixes **both** issues?

- **A.** Use `f.invoice_date >= d.valid_from AND f.invoice_date < d.valid_to` for the join, and `d.tier IS DISTINCT FROM src.tier` in the ETL change check.
- **B.** Use `f.invoice_date > d.valid_from AND f.invoice_date <= d.valid_to` for the join, and `d.tier != src.tier` in the ETL change check.
- **C.** Add `AND d.is_current = TRUE` to the join, and use `NULLIF(d.tier, src.tier)` in the ETL change check.
- **D.** Use `BETWEEN d.valid_from AND d.valid_to` with `DISTINCT f.invoice_id` in `SELECT`, and `d.tier = src.tier` in the ETL check.

---

## Question 4 — CDC & SCD Type 2: Out-of-Order Timeline Reconstruction *(Write the Query)*

A downstream microservice suffered a network outage and delivered a historical `2024-03-01` plan-change event **after** the `2024-05-01` event was already in `cdc_subscription_events`. Additionally, `A-20` emitted a redundant no-op snapshot on `2024-04-01` where `plan_tier` did not change.

**Sample Data — `cdc_subscription_events`:**

| account_id | plan_tier  | effective_date | _ingested_at        |
|------------|------------|----------------|---------------------|
| A-10       | free       | 2024-01-01     | 2024-01-01 00:05:00 |
| A-10       | enterprise | 2024-05-01     | 2024-05-01 09:00:00 |
| A-10       | pro        | 2024-03-01     | 2024-05-10 10:00:00 |
| A-20       | starter    | 2024-02-01     | 2024-02-01 01:00:00 |
| A-20       | starter    | 2024-04-01     | 2024-04-01 01:00:00 |

**Task:** Write an ANSI SQL query to reconstruct clean, non-overlapping SCD Type 2 rows `(account_id, plan_tier, valid_from, valid_to, is_current)` using `DATE '9999-12-31'` as the open sentinel `valid_to`, collapsing consecutive unchanged snapshots (`A-20` on `2024-04-01`) and placing `A-10`'s late `2024-03-01` event in its proper chronological slot.

---

## Question 5 — Gaps & Islands: Longest Consecutive Active Streak *(Write the Query)*

Product wants to know each user's **longest** consecutive-day active streak (`longest_streak_days`, along with its `streak_start` and `streak_end` dates). Note that `user_activity` stores timestamped events and users frequently log in multiple times on the same calendar day.

**Sample Data — `user_activity`:**

| user_id | login_ts            |
|---------|---------------------|
| U1      | 2024-05-01 08:00:00 |
| U1      | 2024-05-01 21:00:00 |
| U1      | 2024-05-02 09:00:00 |
| U1      | 2024-05-03 10:00:00 |
| U1      | 2024-05-05 11:00:00 |
| U2      | 2024-05-01 12:00:00 |
| U2      | 2024-05-02 12:00:00 |
| U2      | 2024-05-04 12:00:00 |
| U2      | 2024-05-05 12:00:00 |
| U2      | 2024-05-06 12:00:00 |

**Task:** Write an ANSI SQL query returning `(user_id, streak_start, streak_end, longest_streak_days)` with one row per user (for the longest streak).

---

## Question 6 — Gaps & Islands: Grouping Contiguous Server Status Ranges *(Write the Query)*

An observability pipeline collects periodic health pings in `server_pings`. You need to compress consecutive pings of the same `status` into contiguous status intervals.

**Sample Data — `server_pings`:**

| server_id | ping_id | ping_ts             | status   |
|-----------|---------|---------------------|----------|
| api-1     | 1       | 2024-05-01 00:00:00 | HEALTHY  |
| api-1     | 2       | 2024-05-01 00:01:00 | HEALTHY  |
| api-1     | 3       | 2024-05-01 00:02:00 | DEGRADED |
| api-1     | 4       | 2024-05-01 00:03:00 | HEALTHY  |
| api-1     | 5       | 2024-05-01 00:04:00 | HEALTHY  |

**Task:** Write an ANSI SQL query returning `(server_id, status, period_start, period_end, ping_count)` ordered by `server_id, period_start`, ensuring that `api-1`'s first `HEALTHY` interval (`00:00`–`00:01`) and second `HEALTHY` interval (`00:03`–`00:04`) are **not** merged together.

---

## Question 7 — Sessionization: 30-Minute Clickstream Sessions *(Write the Query)*

Your analytics team defines a web session using a **strictly greater than 30-minute** (`> INTERVAL '30' MINUTE`) inactivity timeout. Two events from the same user occurring exactly 30 minutes apart remain in the same session; a gap of 31 minutes starts a new session.

**Sample Data — `web_events`:**

| user_id | event_id | event_ts            | page      |
|---------|----------|---------------------|-----------|
| u1      | e1       | 2024-05-01 10:00:00 | /home     |
| u1      | e2       | 2024-05-01 10:15:00 | /pricing  |
| u1      | e3       | 2024-05-01 10:45:00 | /checkout |
| u1      | e4       | 2024-05-01 11:16:00 | /home     |
| u2      | e5       | 2024-05-01 10:05:00 | /docs     |
| u2      | e6       | 2024-05-01 10:05:00 | /api      |

**Task:** Write a SQL query that assigns deterministic sessions (`user_id || '-' || session_seq`) and returns `(user_id, global_session_id, session_start, session_end, event_count)`.

---

## Question 8 — Sessionization: Boundary & `DATEDIFF` Pitfalls *(Multiple Choice)*

A colleague writes a Snowflake sessionization model using `DATEDIFF('minute', prev_event_ts, event_ts) > 30` and runs it incrementally on strictly disjoint daily partitions (`WHERE DATE(event_ts) = :run_date`). During review, you spot **two** serious bugs:

1. Event A occurs at `10:00:59` and Event B occurs at `10:31:01` (elapsed time: **30 minutes and 2 seconds**). What does `DATEDIFF('minute', '10:00:59', '10:31:01')` return, and what happens to a session spanning `23:50` on May 1 to `00:10` on May 2?

- **A.** `DATEDIFF('minute', ...)` returns `30` (misses the `> 30` split even though >30m elapsed), and the midnight session is incorrectly split into two separate sessions across the two daily batch runs.
- **B.** `DATEDIFF('minute', ...)` returns `31` (triggers the split accurately), and the midnight session is merged cleanly across batches.
- **C.** `DATEDIFF('minute', ...)` returns `30` (misses the split), while daily partition filtering automatically connects sessions across midnight.
- **D.** `DATEDIFF('minute', ...)` returns `31` (triggers the split), and the midnight session is split into two sessions across the two daily batch runs.

---

## Question 9 — Semi-Structured Data: Flattening Arrays Without Dropping Empty Parents *(Write the Query)*

A staging table `raw_api_orders` stores JSON payloads in a `payload` column (`JSONB` in PostgreSQL, `VARIANT` in Snowflake, or `JSON` in BigQuery). You need to extract `order_id` and explode the `items` array to compute `line_total = quantity * price`, keeping **only** items with `price >= 20.00`, **while still retaining orders whose `items` array is empty or contains no items >= $20.00** (with `NULL` for item columns).

**Sample Data — `raw_api_orders`:**

| id | payload |
|----|---------|
| 1  | `{"order_id": "O-10", "items": [{"sku": "S1", "qty": 2, "price": 25.00}, {"sku": "S2", "qty": 1, "price": 12.00}]}` |
| 2  | `{"order_id": "O-11", "items": []}` |
| 3  | `{"order_id": "O-12", "items": [{"sku": "S3", "qty": 4, "price": 5.00}]}` |

**Task:** Write the query (in PostgreSQL `JSONB`, BigQuery, or Snowflake syntax—explicitly noting which dialect you chose) returning `(order_id, sku, qty, price, line_total)` for all 3 parent orders (`O-10` with `S1`, `O-11` with `NULL`s, and `O-12` with `NULL`s).

---

## Question 10 — Idempotent Ingestion: `MERGE INTO` & Watermark Pitfalls *(Multiple Choice)*

An Airflow pipeline loads `clean_events` incrementally every hour using:

```sql
MERGE INTO clean_events AS tgt
USING (
    SELECT event_id, event_time, status
    FROM raw_events
    WHERE event_time > (SELECT MAX(event_time) FROM clean_events)
) AS src
  ON tgt.event_id = src.event_id
WHEN MATCHED THEN UPDATE SET tgt.status = src.status
WHEN NOT MATCHED THEN INSERT (event_id, event_time, status)
    VALUES (src.event_id, src.event_time, src.status);
```

This job suffers from **two** production incidents:
1. It crashes whenever `raw_events` receives two updates for the same `event_id` in one hour.
2. Late-arriving events whose `event_time` is earlier than the latest event already in `clean_events` are silently never ingested.

What fixes **both** incidents?

- **A.** Replace `MERGE INTO` with `INSERT OVERWRITE` and change `>` to `>=` in the `WHERE` filter.
- **B.** Deduplicate `raw_events` with `ROW_NUMBER()` inside the `USING` subquery, and watermark on monotonic `_ingested_at` (or apply a lookback buffer on `event_time` paired with `MERGE`).
- **C.** Remove the `ON tgt.event_id = src.event_id` clause and add `DISTINCT` to `SELECT event_id, event_time, status`.
- **D.** Change `WHEN MATCHED` to `WHEN MATCHED AND src.event_time < tgt.event_time` and keep `WHERE event_time > (SELECT MAX(event_time) FROM clean_events)`.

---

## Question 11 — Idempotent Ingestion: Deduplicated `MERGE INTO` with Soft Deletes *(Write the Query)*

Your daily warehouse sync loads `stg_inventory` into `dim_inventory`. The staging batch can contain duplicate keys, out-of-order stale records, new SKUs, and tombstone rows (`is_deleted = TRUE`).

**Existing — `dim_inventory`:**

| sku  | stock_qty | updated_at          |
|------|-----------|---------------------|
| SK-1 | 10        | 2024-05-01 08:00:00 |
| SK-2 | 50        | 2024-05-01 08:00:00 |
| SK-3 | 20        | 2024-05-01 08:00:00 |

**Incoming — `stg_inventory`:**

| sku  | stock_qty | updated_at          | is_deleted |
|------|-----------|---------------------|------------|
| SK-1 | 15        | 2024-05-02 07:00:00 | FALSE      |
| SK-1 | 18        | 2024-05-02 09:00:00 | FALSE      |
| SK-2 | 99        | 2024-04-28 08:00:00 | FALSE      |
| SK-3 | 0         | 2024-05-02 09:00:00 | TRUE       |
| SK-4 | 40        | 2024-05-02 09:00:00 | FALSE      |
| SK-5 | 12        | 2024-05-02 09:00:00 | TRUE       |

**Task:** Write an idempotent `MERGE INTO` statement that leaves `dim_inventory` with `SK-1` (`18`), `SK-2` unchanged (`50`), `SK-3` deleted, `SK-4` inserted (`40`), and `SK-5` not inserted.

---

## Question 12 — Calendar Spines, Timezones & DST *(Write the Query)*

Finance wants a daily revenue report in **`America/New_York`** local business dates for **`2024-03-09` through `2024-03-12`**, counting **only `'paid'` orders** (`status = 'paid'`). Note that US Daylight Saving Time sprang forward on `2024-03-10` at `07:00:00 UTC` (`02:00 EST` → `03:00 EDT`). Every date in the range must appear in the output, even days with zero paid orders.

**Sample Data — `orders` (`order_ts_utc` stored as timezone-aware UTC `TIMESTAMPTZ`):**

| order_id | order_ts_utc           | status    | amount |
|----------|------------------------|-----------|--------|
| 101      | 2024-03-10 04:30:00+00 | paid      | 100.00 |
| 102      | 2024-03-10 07:30:00+00 | paid      | 50.00  |
| 103      | 2024-03-10 12:00:00+00 | cancelled | 80.00  |
| 104      | 2024-03-11 04:30:00+00 | paid      | 40.00  |

**Task:** Write an ANSI/PostgreSQL SQL query using a recursive calendar spine, `AT TIME ZONE 'America/New_York'`, and a safe `LEFT JOIN` that preserves all 4 calendar dates. State the exact expected output table.
