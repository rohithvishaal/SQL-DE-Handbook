# Module 5 Solutions: Query Performance, Optimization & Anti-Patterns

> Full diagnostics, anti-pattern explanations, and optimized rewrites for the [Module 5 Quiz](quiz.md).

---

## Solution 1: Diagnosing an Execution Plan (`EXPLAIN ANALYZE` / Query Profile)

### 1. Three Bottlenecks Revealed
1. **Zero Partition Pruning (`Partitions Pruned: 0 / 730` at Node 1):** The query scanned the entire 2-year history of `fact_orders` instead of pruning to the target date window (likely caused by a missing date filter or a non-SARGable function on the partition key).
2. **Join Fan-Out / Row Explosion (`Rows In: 120M + 50K -> Rows Out: 1.8B` at Node 3):** `dim_promotions` is not unique on `promo_code` (averaging ~15 matching rows per order), multiplying the dataset 15x from 120 million rows to **1.8 billion rows**.
3. **Remote Disk Spill (`Spill to Remote Storage: 64 GB` at Node 4):** `WindowSort` ran out of the 16 GB node memory buffer and spilled intermediate sorted runs to remote object storage (S3/GCS), introducing massive network I/O latency.

### 2. Root Cause of the Spill
The **15x join fan-out at Node 3** directly caused Node 4's remote disk spill. Sorting 1.8 billion rows instead of 120 million rows exceeded available RAM by 64 GB. Deduplicating `dim_promotions` on `promo_code` before the join immediately eliminates the 15x blowup and drops spill back to `0`.

> [!TIP]
> Whenever you see high spill in a downstream `Window` or `Aggregate` operator, check the `Join` operators **below** it first — an unexpected `Rows Out > Rows In` ratio is often the true culprit.

---

## Solution 2: Non-SARGable Predicate Defeating Partition Pruning

### 1. Three Performance Anti-Patterns
1. **`SELECT *` on a 18 TB columnar table:** Reads every single column off storage rather than only the few columns needed by the dashboard, inflating I/O and BigQuery bytes-billed costs.
2. **Non-SARGable `TO_CHAR(session_start_ts, 'YYYY-MM') = '2026-02'`:** Wrapping `session_start_ts` in a formatting function defeats partition pruning, forcing a full 18 TB scan across every historical partition.
3. **Non-SARGable `LOWER(country_code) = 'us'`:** Wrapping the cluster key `country_code` in `LOWER()` prevents block/cluster metadata pruning (min/max zone maps store uppercase `'US'`, not lowercase `'us'`).

### 2. Optimized Query Rewrite

```sql
SELECT
    session_id,
    user_id,
    session_start_ts,
    country_code,
    device_type
FROM analytics.fact_sessions
WHERE session_start_ts >= TIMESTAMP '2026-02-01 00:00:00'
  AND session_start_ts <  TIMESTAMP '2026-03-01 00:00:00'
  AND country_code IN ('US', 'us'); -- Or standardize to 'US' at ingestion
```

> [!WARNING]
> Always use half-open range boundaries (`>=` start and `<` exclusive end) for timestamp filters. Using `BETWEEN '2026-02-01' AND '2026-02-28'` silently drops events occurring on Feb 28 after `00:00:00`!

---

## Solution 3: Physical Data Layout & the "Small Files Problem"

### 1. Why `PARTITIONED BY (device_id, event_ts)` Failed
Both `device_id` (thousands/millions of sensors) and `event_ts` (millisecond-level timestamps) have **extreme cardinality**. Hive-style `PARTITIONED BY` creates a separate physical directory for every unique `(device_id, event_ts)` combination — generating 18 million tiny 4 KB Parquet files in 3 days. Listing millions of files overwhelms the Spark driver's memory and storage metadata APIs.

### 2. Best-Practice DDL Rewrites

**Databricks (Delta Lake) — Liquid Clustering (recommended) or coarse Date Partition + Z-Order:**
```sql
-- Option A: Delta Lake Liquid Clustering (auto-manages layout without rigid directories)
CREATE TABLE bronze.iot_telemetry (
    device_id   STRING,
    event_ts    TIMESTAMP,
    sensor_type STRING,
    reading     DOUBLE
)
USING DELTA
CLUSTER BY (event_ts, device_id);

-- Option B: Classic coarse date partition + Z-Order
CREATE TABLE bronze.iot_telemetry (
    device_id   STRING,
    event_ts    TIMESTAMP,
    event_date  DATE GENERATED ALWAYS AS (CAST(event_ts AS DATE)),
    sensor_type STRING,
    reading     DOUBLE
)
USING DELTA
PARTITIONED BY (event_date);

-- Periodically compact & colocate files by device_id:
OPTIMIZE bronze.iot_telemetry ZORDER BY (device_id);
```

**Google BigQuery — Coarse Date Partition + High-Cardinality Cluster:**
```sql
CREATE TABLE `bronze.iot_telemetry` (
    device_id   STRING,
    event_ts    TIMESTAMP,
    sensor_type STRING,
    reading     FLOAT64
)
PARTITION BY DATE(event_ts)
CLUSTER BY device_id
OPTIONS (require_partition_filter = TRUE);
```

> [!TIP]
> **Partition coarse, cluster fine.** Partitioning should yield ~1 GB+ per partition (typically `DATE` or `MONTH`), while `CLUSTER BY` / `ZORDER BY` handles high-cardinality lookup columns like `device_id` or `tenant_id`.

---

## Solution 4: Silent Fan-Out & Band-Aid `SELECT DISTINCT`

### 1. Wrong Math & Why `SELECT DISTINCT` Fails
Joining `orders` directly to both `order_payments` (2 rows) and `order_items` (3 rows) produces a **`2 × 3 = 6`-row Cartesian product** for order `#9001` *before* `GROUP BY` runs:
- **True `total_paid`:** `$30 + $70 = $100` → **Query returns `$300`** (each payment counted 3 times).
- **True `total_weight`:** `200g + 300g + 500g = 1,000g` → **Query returns `2,000g`** (each item counted 2 times).

`SELECT DISTINCT` executes **after** `GROUP BY` — at that point there is already only a single row `(9001, cust_id, 300, 2000)`, so `DISTINCT` does **nothing** to repair the inflated sums.

### 2. Correct Rewrite (Aggregate Child Tables to Parent Grain First)

```sql
WITH payments_by_order AS (
    SELECT
        order_id,
        SUM(paid_amount) AS total_paid
    FROM order_payments
    GROUP BY order_id
),
items_by_order AS (
    SELECT
        order_id,
        SUM(weight_grams) AS total_weight
    FROM order_items
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    COALESCE(p.total_paid, 0)   AS total_paid,
    COALESCE(i.total_weight, 0) AS total_weight
FROM orders o
LEFT JOIN payments_by_order p ON o.order_id = p.order_id
LEFT JOIN items_by_order    i ON o.order_id = i.order_id;
```

> [!WARNING]
> **Never use `SELECT DISTINCT` to paper over duplicate rows from a join.** If a `1-to-N` or `M-to-N` fan-out occurred, `SUM()` and `COUNT()` have already been corrupted prior to `DISTINCT`.

---

## Solution 5: Eliminating Data Skew via Key Salting

### 1. Why One Task Stalled and Crashed
In both a Hash Join and Sort-Merge Join, the engine hashes the join key (`hash(user_id) % num_partitions`) to route matching keys to the same worker. Because 35% of all 10 billion rows (~3.5 billion rows!) share the exact same key `'GUEST_CHECKOUT'`, all 3.5 billion rows hash to **one single partition** (Task #100), starving the other 99 workers and overflowing Task #100's executor memory.

### 2. 10-Bucket Key Salting Rewrite

```sql
WITH salted_clickstream AS (
    SELECT
        event_id,
        event_ts,
        user_id,
        -- Salt ONLY the skewed key across 10 random buckets [0..9]
        CASE
            WHEN user_id = 'GUEST_CHECKOUT'
            THEN CONCAT('GUEST_CHECKOUT_', CAST(FLOOR(RAND() * 10) AS INT))
            ELSE user_id
        END AS salted_user_id
    FROM clickstream_events
),
salted_dim_users AS (
    -- Normal users stay 1x
    SELECT
        user_id AS salted_user_id,
        user_segment,
        country
    FROM dim_users
    WHERE user_id != 'GUEST_CHECKOUT'

    UNION ALL

    -- Replicate ONLY the skewed dimension row 10x across buckets [0..9]
    SELECT
        CONCAT('GUEST_CHECKOUT_', bucket) AS salted_user_id,
        u.user_segment,
        u.country
    FROM dim_users u
    LATERAL VIEW EXPLODE(SEQUENCE(0, 9)) t AS bucket
    WHERE u.user_id = 'GUEST_CHECKOUT'
)
SELECT
    c.event_id,
    c.event_ts,
    c.user_id,
    u.user_segment,
    u.country
FROM salted_clickstream c
LEFT JOIN salted_dim_users u
    ON c.salted_user_id = u.salted_user_id;
```

> [!TIP]
> Notice we only salted `'GUEST_CHECKOUT'` rather than exploding the entire 50M-row `dim_users` table 10x! Also check whether `dim_users` can simply be **Broadcast** (`/*+ BROADCAST(u) */`) or handled natively by Spark Adaptive Query Execution (`spark.sql.adaptive.skewJoin.enabled = true`) before adding manual salt logic.

---

## Solution 6: Implicit Type Conversion & Over-Grouping

### 1. Why It Crashes and Defeats Pruning
- **Intermittent Crash:** When joining `BIGINT` (`fact_transactions.merchant_id`) to `VARCHAR` (`dim_merchants.merchant_id`), SQL engines follow type-precedence rules and implicitly cast the **string column to numeric (`CAST(m.merchant_id AS BIGINT)`)**. The moment a single non-numeric string like `'PENDING_REVIEW'` exists in `dim_merchants`, the runtime cast throws an error and fails the job.
- **Disabled Pruning:** If the implicit cast happens on the fact side (or prevents matching the fact table's min/max metadata types), zone-map pruning degrades and CPU cycles are wasted casting billions of rows.

### 2. Fixing Over-Grouping & Type Mismatch
Group the 2-billion-row fact table **only by the single 8-byte `BIGINT` `merchant_id`** first (avoiding shuffling 6 wide `VARCHAR` columns per transaction), and cast safely using `TRY_CAST` on the small 100K-row dimension table (or cast `BIGINT` to `VARCHAR` depending on canonical key format):

```sql
WITH merchant_gmv AS (
    -- Step 1: Aggregate 2B rows on a single compact BIGINT key
    SELECT
        merchant_id,
        SUM(amount) AS gmv
    FROM fact_transactions
    GROUP BY merchant_id
),
clean_merchants AS (
    -- Step 2: Safely align the dimension key type (filters/nulls dirty rows)
    SELECT
        TRY_CAST(merchant_id AS BIGINT) AS merchant_id_num,
        merchant_id                     AS raw_merchant_id,
        merchant_name,
        category,
        country,
        account_owner,
        onboarding_date
    FROM dim_merchants
    WHERE TRY_CAST(merchant_id AS BIGINT) IS NOT NULL
)
SELECT
    m.merchant_id_num AS merchant_id,
    m.merchant_name,
    m.category,
    m.country,
    m.account_owner,
    m.onboarding_date,
    g.gmv
FROM merchant_gmv g
JOIN clean_merchants m
  ON g.merchant_id = m.merchant_id_num;
```

> [!WARNING]
> **Never rely on implicit type coercion in join keys.** Always validate and align primary/foreign key data types in your Silver/staging models so joins compare identical types (`BIGINT = BIGINT` or `STRING = STRING`).

---

## Solution 7: CTE Materialization Trap in Cloud Warehouses

### 1. Why BigQuery Scanned 32 TB Instead of 8 TB
BigQuery **inlines CTEs** by default (expanding the CTE definition like a macro everywhere it is referenced) and does **not** automatically materialize a CTE that is referenced multiple times. Because `attributed_sessions` appeared in **4 separate `UNION ALL` branches**, BigQuery executed the 8 TB join **4 independent times** (`4 × 8 TB = 32 TB`).

### 2. Two Rewrites That Scan Base Tables Only Once (≤ 8 TB)

**Approach A: Single-Pass Query with `GROUPING SETS` (Pure SQL, 1 scan)**
Filtering `i.channel IN ('SEM', 'SOCIAL', 'DISPLAY')` inside the query and using `GROUPING SETS ((channel), ())` computes all 3 individual channel totals and the combined `'all_paid'` rollup in a **single pass**:

```sql
WITH attributed_sessions AS (
    SELECT
        i.channel,
        s.revenue
    FROM raw.sessions s
    JOIN raw.ad_impressions i
      ON s.user_id = i.user_id
     AND s.session_ts BETWEEN i.impression_ts AND TIMESTAMP_ADD(i.impression_ts, INTERVAL 7 DAY)
    WHERE s.session_date >= '2026-01-01'
      AND i.channel IN ('SEM', 'SOCIAL', 'DISPLAY')
)
SELECT
    CASE
        WHEN GROUPING(channel) = 1 THEN 'all_paid'
        WHEN channel = 'SEM'       THEN 'paid_search'
        WHEN channel = 'SOCIAL'    THEN 'social'
        WHEN channel = 'DISPLAY'   THEN 'display'
    END AS report_slice,
    SUM(revenue) AS rev
FROM attributed_sessions
GROUP BY GROUPING SETS ((channel), ());
```

**Approach B: Explicit `TEMP TABLE` Materialization (BigQuery Scripting)**
Materialize the heavy join once into a session-scoped temporary table before running the `UNION ALL`:

```sql
CREATE TEMP TABLE tmp_attributed_sessions AS
SELECT
    s.session_id,
    s.user_id,
    i.channel,
    s.revenue
FROM raw.sessions s
JOIN raw.ad_impressions i
  ON s.user_id = i.user_id
 AND s.session_ts BETWEEN i.impression_ts AND TIMESTAMP_ADD(i.impression_ts, INTERVAL 7 DAY)
WHERE s.session_date >= '2026-01-01'
  AND i.channel IN ('SEM', 'SOCIAL', 'DISPLAY');

SELECT 'paid_search' AS report_slice, SUM(revenue) AS rev FROM tmp_attributed_sessions WHERE channel = 'SEM'
UNION ALL
SELECT 'social'      AS report_slice, SUM(revenue) AS rev FROM tmp_attributed_sessions WHERE channel = 'SOCIAL'
UNION ALL
SELECT 'display'     AS report_slice, SUM(revenue) AS rev FROM tmp_attributed_sessions WHERE channel = 'DISPLAY'
UNION ALL
SELECT 'all_paid'    AS report_slice, SUM(revenue) AS rev FROM tmp_attributed_sessions;
```

> [!TIP]
> **Prefer Approach A (`GROUPING SETS` or conditional aggregation) whenever possible** — it avoids writing intermediate data to temporary storage and works in standard dbt models or views where multi-statement `CREATE TEMP TABLE` scripts aren't allowed.

---

## Solution 8: Stale Table Statistics & Join Strategy Selection

### 1. Why Spark Chose Sort-Merge Join
For an external non-Delta Parquet table, Spark's Cost-Based Optimizer (CBO) relies on metastore statistics (`sizeInBytes`) to decide whether a table fits under `spark.sql.autoBroadcastJoinThreshold` (default 10 MB). Because stats were missing or stale, Spark fell back to a conservative large-table estimate and picked a **Sort-Merge Join**, needlessly shuffling 4 TB of `fact_ledger`.

### 2. Two Ways to Fix It

**Fix 1: Collect table statistics so CBO knows the true 1.5 MB size**
```sql
ANALYZE TABLE dim_currency_rates COMPUTE STATISTICS FOR ALL COLUMNS;
```

**Fix 2: Add an explicit `BROADCAST` optimizer hint in SQL**
```sql
SELECT /*+ BROADCAST(r) */
    l.ledger_id,
    l.amount_local,
    l.amount_local * r.usd_rate AS amount_usd
FROM fact_ledger l
JOIN dim_currency_rates r
  ON l.currency_code = r.currency_code;
```

> [!WARNING]
> Only use `/*+ BROADCAST(...) */` on tables guaranteed to stay well within executor driver/worker memory (typically `< 100 MB`). If a hinted dimension table silently grows to 5 GB over time, the job will crash with an out-of-memory error instead of gracefully falling back to Sort-Merge Join.

---

*← Back to [Module 5 Quiz](quiz.md) | Review [Module 5 Cheatsheet →](../../cheatsheets/05-performance-tuning.md)*
