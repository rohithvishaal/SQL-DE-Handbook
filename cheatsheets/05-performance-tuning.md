# Module 5: Query Performance, Optimization & Anti-Patterns

> How cloud analytical engines execute SQL under the hood — reading query plans, leveraging physical data layout, choosing join strategies, eliminating skew, and refactoring slow anti-patterns.

---

## Table of Contents

1. [Reading Execution Plans: `EXPLAIN` and `EXPLAIN ANALYZE`](#1-reading-execution-plans-explain-and-explain-analyze)
2. [Physical Data Layout & Pruning](#2-physical-data-layout--pruning)
3. [Join Strategies & Handling Data Skew](#3-join-strategies--handling-data-skew)
4. [SQL Anti-Patterns & Rewrites](#4-sql-anti-patterns--rewrites)
5. [Index and Statistics Awareness](#5-index-and-statistics-awareness)
6. [CTE Materialization Behavior Across Engines](#6-cte-materialization-behavior-across-engines)

---

## 1. Reading Execution Plans: `EXPLAIN` and `EXPLAIN ANALYZE`

An execution plan is the directed acyclic graph (DAG) of physical operators an engine uses to compute your query. `EXPLAIN` compiles the query and prints the **estimated** plan without executing it, whereas `EXPLAIN ANALYZE` runs the query and overlays **actual** runtime metrics (rows processed, execution time, memory, and disk spill).

Reading execution plans is the fastest way to distinguish an I/O bottleneck (scanning too much data) from a compute/network bottleneck (shuffling, skew, or memory spills).

### Platform Syntax Comparison

| Capability | ANSI / DuckDB | Snowflake | BigQuery | Databricks (Spark SQL) |
|---|---|---|---|---|
| Estimated Plan | `EXPLAIN SELECT ...` | `EXPLAIN USING TEXT SELECT ...` | Dry Run / Execution Plan tab | `EXPLAIN FORMATTED SELECT ...` |
| Actual Runtime Plan | `EXPLAIN ANALYZE SELECT ...` | Query Profile UI / `GET_QUERY_OPERATOR_STATS()` | Job Execution Details UI | Spark UI (SQL / DAG tab) |
| Cost / Bytes Estimate | `EXPLAIN` output | `partitionsTotal`, `partitionsAssigned` | `totalBytesProcessed` (Dry Run) | `EXPLAIN COST` (with stats) |

### Key Plan Signals to Diagnose

| Operator / Metric | What It Means | Healthy Signal | Red Flag |
|---|---|---|---|
| **TableScan / SeqScan** | Reading storage blocks/files | `Partitions pruned: 360/365` | `Full table scan`, high `Bytes scanned` |
| **Exchange / Shuffle** | Moving rows across worker nodes | Small payload, filtered prior to shuffle | Multi-TB shuffle before filtering |
| **Spill (Local / Remote)** | Hash table or sort buffer exceeded RAM | `0 bytes spilled` | `Bytes spilled to remote storage > 0` |
| **Join** | Combining two relations | `Actual rows` ≈ `Estimated rows` | Output rows 100x larger than input (fan-out) |

```sql
-- DuckDB: inspect actual operator timings, cardinality, and memory usage
EXPLAIN ANALYZE
SELECT
    c.region,
    COUNT(o.order_id) AS total_orders,
    SUM(o.amount)     AS gross_revenue
FROM fact_orders o
JOIN dim_customers c ON o.customer_id = c.customer_id
WHERE o.order_date >= DATE '2026-01-01'
GROUP BY c.region;
```

```text
-- Example EXPLAIN ANALYZE output snippet (read bottom-up: Scans -> Join -> Aggregate)
┌───────────────────────────┐
│       HASH_GROUP_BY       │  Actual Rows: 5       | Time: 0.12s
└─────────────┬─────────────┘
              │
┌─────────────┴─────────────┐
│         HASH_JOIN         │  Actual Rows: 4.2M    | Time: 0.85s | Build: dim_customers
└──────┬─────────────┬──────┘
       │             │
┌──────┴──────┐ ┌────┴────────┐
│  SEQ_SCAN   │ │  SEQ_SCAN   │
│ fact_orders │ │dim_customers│
│ Rows: 4.2M  │ │ Rows: 250K  │
│ Filter: >=  │ └─────────────┘
└─────────────┘
```

**Scenario — Diagnosing a nightly ELT job that slowed from 2 minutes to 45 minutes:**
Looking at the Snowflake Query Profile (or `GET_QUERY_OPERATOR_STATS`), you see `WindowFunction` spilled **180 GB to local disk** and **42 GB to remote storage** because an upstream `JOIN` lacked a deduplication filter and multiplied rows 50x before the window sort.

> [!WARNING]
> **Remote disk spill is a silent performance killer.** Local SSD spill slows queries down 2–5x, but spilling to remote object storage (S3/GCS/Azure Blob) can make a query 20–100x slower. Watch for spill metrics whenever running large `ORDER BY`, `GROUP BY`, or `WINDOW` operations.

> [!TIP]
> Always read execution plans **from the leaves (scans) up to the root**, checking two numbers at every node: **rows in vs. rows out** (to spot silent join fan-outs) and **partitions pruned vs. total** (to confirm filter pushdown).

---

## 2. Physical Data Layout & Pruning

Analytical cloud warehouses store data in compressed, columnar blocks (files, micro-partitions, or Parquet row groups) along with metadata headers recording the `MIN` and `MAX` values of each column per block. When your `WHERE` clause aligns with the physical ordering of those blocks, the engine skips irrelevant blocks entirely — a process called **pruning**.

Understanding how your warehouse organizes physical storage lets you shrink a 50 TB query down to a 50 GB scan with zero change to business logic.

### Physical Storage Mechanisms Across Platforms

| Mechanism | DuckDB | Snowflake | BigQuery | Databricks (Delta Lake) |
|---|---|---|---|---|
| **Coarse Partitioning** | Hive-partitioned Parquet folders | Automatic Micro-partitions (50–500 MB uncompressed) | `PARTITION BY` (Day/Hour/Range) | `PARTITIONED BY` (Hive folders) or Liquid Clustering |
| **Fine Clustering / Sorting** | Sort on write (`ORDER BY` before `COPY`) | `CLUSTER BY (col1, col2)` | `CLUSTER BY col1, col2` (max 4 cols) | `OPTIMIZE ... ZORDER BY` or `CLUSTER BY` (Liquid) |
| **Metadata Pruning** | Row-group min/max zone maps | Micro-partition min/max metadata | Block-level metadata per cluster | Delta log min/max stats (first 32 cols) |

### Code Comparison: Defining Optimal Physical Layout

```sql
-- BigQuery: Partition by event date (coarse), cluster by tenant and event type (fine)
CREATE TABLE `analytics.fact_events` (
    event_id   STRING,
    event_ts   TIMESTAMP,
    tenant_id  STRING,
    event_type STRING,
    payload    JSON
)
PARTITION BY DATE(event_ts)
CLUSTER BY tenant_id, event_type
OPTIONS (require_partition_filter = TRUE);

-- Snowflake: Automatic micro-partitions + explicit clustering key
CREATE OR REPLACE TABLE analytics.fact_events (
    event_id   VARCHAR,
    event_ts   TIMESTAMP_NTZ,
    tenant_id  VARCHAR,
    event_type VARCHAR,
    payload    VARIANT
)
CLUSTER BY (TO_DATE(event_ts), tenant_id);

-- Databricks (Delta Lake): Liquid Clustering (replaces legacy PARTITIONED BY + ZORDER)
CREATE TABLE analytics.fact_events (
    event_id   STRING,
    event_ts   TIMESTAMP,
    tenant_id  STRING,
    event_type STRING,
    payload    STRING
)
USING DELTA
CLUSTER BY (tenant_id, event_ts);
```

**Scenario — Pruning a 40 TB multi-tenant clickstream table:**
A SaaS analytics dashboard filters every query by `tenant_id` and the last 7 days of `event_ts`. Partitioning by `DATE(event_ts)` drops scanned data from 40 TB (all history) to ~500 GB (7 days); clustering by `tenant_id` lets the engine prune inside each day's partitions and scan only **2.4 GB** for that specific tenant.

> [!WARNING]
> **Avoid high-cardinality Hive partitioning.** Creating `PARTITIONED BY (user_id)` or `PARTITIONED BY (event_id)` in Spark/Delta or Hive-style lakes generates millions of tiny files (the "small files problem"), turning metadata listing slower than the query itself. Reserve `PARTITION BY` for coarse, low-cardinality boundaries (typically `DATE` or `MONTH`) where each partition holds at least ~1 GB.

> [!TIP]
> Put your **most frequent equality/range filter column first** in `CLUSTER BY` (or low-to-medium cardinality before high cardinality), and enforce `require_partition_filter = TRUE` in BigQuery on massive fact tables to block accidental full-table scans from BI tools.

---

## 3. Join Strategies & Handling Data Skew

Distributed query engines execute joins differently depending on table sizes, sort order, and cluster memory. Picking the wrong join strategy — or feeding a skewed join key into a distributed shuffle — causes one worker node to choke on 90% of the data while 99 other workers sit idle.

### Join Algorithms Compared

| Join Strategy | How It Works | Ideal When | Cost / Bottleneck |
|---|---|---|---|
| **Broadcast (Map-Side) Join** | Copies the entire smaller table to every worker node | One table is small (e.g., `< 10–100 MB` dimension table) | Memory on workers if small side grows too large |
| **Shuffle Hash Join** | Hashes join key on both tables, shuffles matching keys to same node, builds hash table | Medium-to-large tables that fit in per-partition RAM | Network shuffle + OOM risk on skewed partitions |
| **Sort-Merge Join** | Shuffles and sorts both sides by join key, then streams and merges | Two massive tables (hundreds of GBs to TBs) | High CPU & memory cost for sorting both inputs |

```sql
-- Databricks / Spark SQL: Explicitly hint a Broadcast Join when stats are missing
SELECT /*+ BROADCAST(d) */
    f.order_id,
    f.amount,
    d.country_name
FROM fact_orders f
JOIN dim_countries d
    ON f.country_code = d.country_code;
```

### Handling Data Skew (Key Salting)

Data skew occurs when a disproportionate number of rows share a single join key (such as `customer_id IS NULL`, `'guest'`, or `'unknown'`). During a hash or sort-merge join, all rows with that hot key are routed to **one single executor**, causing OOM errors or a 99%-stuck progress bar.

**Salting** appends a random bucket suffix (`0` to `N-1`) to the hot keys on the large fact table and explodes the matching keys on the dimension table `N` times, spreading the skewed key across `N` workers.

```sql
-- Scenario: 40% of clickstream events have user_id = 'ANONYMOUS' (or NULL).
-- Joining directly to dim_users stalls one node. Salt keys across 10 buckets!

WITH salted_events AS (
    SELECT
        event_id,
        COALESCE(user_id, 'ANONYMOUS') AS user_id,
        -- Append a random salt [0..9] ONLY to the skewed key (or all keys)
        CASE
            WHEN COALESCE(user_id, 'ANONYMOUS') = 'ANONYMOUS'
            THEN CONCAT('ANONYMOUS_', CAST(FLOOR(RANDOM() * 10) AS INT))
            ELSE user_id
        END AS salted_user_key
    FROM raw_clickstream
),
salted_dim_users AS (
    -- Normal non-skewed users stay 1x
    SELECT user_id AS salted_user_key, tier, country
    FROM dim_users
    WHERE user_id != 'ANONYMOUS'

    UNION ALL

    -- Expand only the skewed dimension row into 10 copies [0..9]
    SELECT
        CONCAT('ANONYMOUS_', b.bucket) AS salted_user_key,
        u.tier,
        u.country
    FROM dim_users u
    CROSS JOIN (
        -- DuckDB/Spark/Snowflake/BigQuery bucket generator (0..9)
        SELECT 0 AS bucket UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL
        SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL
        SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
    ) b
    WHERE u.user_id = 'ANONYMOUS'
)
SELECT
    e.event_id,
    e.user_id,
    u.tier,
    u.country
FROM salted_events e
LEFT JOIN salted_dim_users u
    ON e.salted_user_key = u.salted_user_key;
```

**Scenario — Unsticking a Spark/Snowflake nightly attribution join:**
Your clickstream-to-user join hangs at 99% for 40 minutes because bot traffic and logged-out sessions all share `user_id = 'GUEST'`. By filtering out `'GUEST'` into a separate branch or applying a 10-way salt to `'GUEST'`, all 10+ worker cores process the traffic in parallel and finish in 90 seconds.

> [!WARNING]
> **Never join on unguarded `NULL`s or sentinel values without checking skew.** Even though `INNER`/`LEFT JOIN` does not match `NULL = NULL`, engines that hash-partition rows before joining—or pipelines that `COALESCE(id, '-1')`—route millions of sentinel rows to the exact same partition.

> [!TIP]
> Before writing manual salting SQL, check if your platform handles skew automatically: Databricks AQE (Adaptive Query Execution) enables **Skew Join Optimization** (`spark.sql.adaptive.skewJoin.enabled = true`) out of the box, and Broadcast Joins eliminate shuffle skew completely whenever one side fits in memory.

---

## 4. SQL Anti-Patterns & Rewrites

Even well-provisioned cloud warehouses crawl when fed anti-patterns that prevent column pruning, disable partition elimination, or multiply row counts prematurely.

### 4.1 `SELECT *` on Columnar Storage

Cloud warehouses (Snowflake, BigQuery, DuckDB, Parquet/Delta) store each column separately on disk. `SELECT *` forces the engine to read, decompress, and transmit **every column** in the table, multiplying both I/O cost and BigQuery bytes-billed charges.

| Bad (Anti-Pattern) | Good (Column-Pruned) |
|---|---|
| ```sql<br>SELECT *<br>FROM raw_events<br>WHERE event_date = '2026-03-01';<br>``` | ```sql<br>SELECT event_id, user_id, revenue<br>FROM raw_events<br>WHERE event_date = '2026-03-01';<br>``` |

> [!WARNING]
> In BigQuery on-demand pricing, `SELECT *` over a 100-column, 10 TB table costs ~$62.50 per run even if you only inspect 2 columns (`SELECT col1, col2` might cost $1.25). Putting `SELECT *` inside a CTE does not always protect you if downstream queries reference `t.*` or non-trivial expressions.

> [!TIP]
> Explicitly list required columns in staging models and use `SELECT * EXCLUDE (col1, col2)` (supported in DuckDB, Snowflake, BigQuery `EXCEPT`, and Databricks) when dropping a few heavy payload columns.

---

### 4.2 Non-SARGable Functions in `WHERE`

**SARGable** stands for *Search ARGument-able*. Wrapping a partitioned, clustered, or indexed column inside a function (e.g., `YEAR(dt) = 2026`, `DATE(ts) = '2026-01-15'`, or `LOWER(email) = ...`) forces the engine to compute the function on **every row** instead of consulting partition/min-max metadata.

| Bad (Defeats Pruning) | Good (SARGable Range Predicate) |
|---|---|
| ```sql<br>SELECT order_id, amount<br>FROM fact_orders<br>WHERE YEAR(order_ts) = 2026<br>  AND MONTH(order_ts) = 3;<br>``` | ```sql<br>SELECT order_id, amount<br>FROM fact_orders<br>WHERE order_ts >= TIMESTAMP '2026-03-01 00:00:00'<br>  AND order_ts <  TIMESTAMP '2026-04-01 00:00:00';<br>``` |

**Scenario — Fixing a dashboard SLA breach:**
A Looker dashboard runs `WHERE TO_CHAR(created_at, 'YYYY-MM') = '2026-03'` against a 2-year Snowflake table, scanning all 730 days of micro-partitions on every load. Rewriting it as `created_at >= '2026-03-01' AND created_at < '2026-04-01'` enables instant micro-partition pruning and cuts execution time from 18 seconds to 400 ms.

> [!WARNING]
> **Watch out for `DATE(timestamp_col) = '2026-03-01'`.** While BigQuery can sometimes prune `PARTITION BY DATE(ts)` when using `DATE(ts) = ...`, Spark, Snowflake, and Postgres/OLTP indexes often fail to prune unless the predicate uses raw half-open boundaries (`>=` and `<`).

> [!TIP]
> Always put the bare column on the left-hand side of a comparison (`col >= ... AND col < ...`), and transform the **constant/literal** on the right-hand side instead of the column.

<ClozeDrill
  card-id="diag-m5-sargable-date"
  module-id="m5"
  prompt="Write a SARGable single-day range filter on event_ts so partition pruning still fires:"
  :prefix="'SELECT order_id, amount\nFROM fact_events\nWHERE '"
  answer="event_ts >= TIMESTAMP '2026-01-15 00:00:00' AND event_ts < TIMESTAMP '2026-01-16 00:00:00'"
  suffix=";"
/>

---

### 4.3 Accidental Cross Joins & Many-to-Many Fan-Outs

Omitting a join key, leaving legacy comma-separated `FROM a, b` syntax without a `WHERE` filter, or joining two tables on non-unique keys produces a Cartesian product (`N * M` rows) that balloons memory and silently inflates `SUM()`/`COUNT()` metrics.

| Bad (Cartesian / Fan-Out Explosion) | Good (Explicit `JOIN` + Pre-Aggregated Keys) |
|---|---|
| ```sql<br>-- Accidental fan-out: user can have 5 payments & 4 refunds<br>SELECT<br>    u.user_id,<br>    SUM(p.amount) AS total_paid,<br>    SUM(r.amount) AS total_refunded<br>FROM users u<br>LEFT JOIN payments p ON u.user_id = p.user_id<br>LEFT JOIN refunds  r ON u.user_id = r.user_id<br>GROUP BY u.user_id;<br>``` | ```sql<br>WITH pay_agg AS (<br>    SELECT user_id, SUM(amount) AS total_paid<br>    FROM payments GROUP BY user_id<br>),<br>ref_agg AS (<br>    SELECT user_id, SUM(amount) AS total_refunded<br>    FROM refunds GROUP BY user_id<br>)<br>SELECT<br>    u.user_id,<br>    COALESCE(p.total_paid, 0)     AS total_paid,<br>    COALESCE(r.total_refunded, 0) AS total_refunded<br>FROM users u<br>LEFT JOIN pay_agg p ON u.user_id = p.user_id<br>LEFT JOIN ref_agg r ON u.user_id = r.user_id;<br>``` |

> [!WARNING]
> In the "Bad" query above, a user with 5 payments and 4 refunds generates `5 × 4 = 20` rows before `GROUP BY`, multiplying `total_paid` by 4 and `total_refunded` by 5 — with **zero SQL errors**.

> [!TIP]
> Never join two 1-to-many child tables directly to the same parent in one `SELECT`. Aggregate each child table to the parent grain in separate CTEs first, then join `1-to-1`.

---

### 4.4 Implicit Type Conversions

Joining or filtering on columns of different data types (for instance, `INT` compared to `VARCHAR`, or `DATE` compared to `TIMESTAMP`) forces the engine to cast values row-by-row at runtime. This disables index/zone-map pruning and can throw runtime conversion errors on dirty string rows.

| Bad (Implicit Cast on Column) | Good (Explicit Matching Types) |
|---|---|
| ```sql<br>-- account_id is BIGINT in fact_tx, VARCHAR in dim_acct<br>SELECT t.tx_id, a.account_name<br>FROM fact_tx t<br>JOIN dim_acct a<br>  ON t.account_id = a.account_id;<br>``` | ```sql<br>-- Align types in staging or cast explicitly on the clean side<br>SELECT t.tx_id, a.account_name<br>FROM fact_tx t<br>JOIN dim_acct a<br>  ON t.account_id = TRY_CAST(a.account_id AS BIGINT);<br>``` |

> [!WARNING]
> If `fact_tx.account_id` (BIGINT) is joined to `dim_acct.account_id` (VARCHAR), engines like SQL Server, Postgres, and Snowflake often cast the **string column to numeric**, crashing the entire pipeline the moment a single non-numeric string like `'N/A'` lands in `dim_acct`.

> [!TIP]
> Standardize join key types (`STRING` or `BIGINT`) in your Bronze-to-Silver staging layer, and use `TRY_CAST` / `SAFE_CAST` when parsing untrusted string identifiers.

---

### 4.5 Over-Grouping & Redundant `DISTINCT`

Using `SELECT DISTINCT` as a band-aid to hide duplicate rows from a bad join—or putting 15 descriptive attributes in `GROUP BY` when grouping by primary key `customer_id`—forces massive multi-column hash tables and wide network shuffles.

| Bad (Wide Group-By + Band-Aid `DISTINCT`) | Good (Aggregate on ID, Then Enrich) |
|---|---|
| ```sql<br>SELECT DISTINCT<br>    c.customer_id, c.full_name, c.email, c.address,<br>    c.city, c.country, SUM(o.amount) AS ltv<br>FROM orders o<br>JOIN customers c ON o.customer_id = c.customer_id<br>GROUP BY 1, 2, 3, 4, 5, 6;<br>``` | ```sql<br>WITH ltv AS (<br>    SELECT customer_id, SUM(amount) AS ltv<br>    FROM orders<br>    GROUP BY customer_id<br>)<br>SELECT c.customer_id, c.full_name, c.email, ltv.ltv<br>FROM ltv<br>JOIN customers c ON ltv.customer_id = c.customer_id;<br>``` |

> [!WARNING]
> Grouping by 6 wide `VARCHAR` columns instead of a single 8-byte `BIGINT` ID inflates the shuffle/hash key size dramatically and can trigger memory spills on large fact-to-dimension aggregations.

> [!TIP]
> **Aggregate first, join dimensions last.** Reduce billions of fact rows down to `(id, metric)` before joining human-readable names, emails, or descriptions.

---

## 5. Index and Statistics Awareness

Query optimizers are cost-based: they rely on table statistics (row counts, distinct value counts `NDV`, null fractions, histograms) to choose join order and select between a Broadcast Join and a Sort-Merge Join. Meanwhile, traditional B-Tree indexes dominate OLTP databases (PostgreSQL, MySQL) whereas cloud data warehouses use lightweight metadata indexes (zone maps, bloom filters, search optimization).

### Metadata & Statistics Maintenance by Engine

| Feature | DuckDB | Snowflake | BigQuery | Databricks (Spark SQL) |
|---|---|---|---|---|
| **B-Tree / Row Indexes** | ART indexes (PK/Unique only) | Search Optimization Service (point lookups) | Search Indexes (`CREATE SEARCH INDEX`) | Bloom Filter Indexes / Z-Order |
| **Statistics Collection** | Automatic during write | Automatic (micro-partition metadata) | Automatic (managed storage) | Manual/Auto (`ANALYZE TABLE`) |
| **Refresh Stats Command** | Automatic | Automatic | Automatic | `ANALYZE TABLE t COMPUTE STATISTICS FOR ALL COLUMNS;` |

```sql
-- Databricks / Spark SQL: Collect table & column stats so CBO picks Broadcast Join
ANALYZE TABLE gold.dim_products COMPUTE STATISTICS FOR ALL COLUMNS;

-- BigQuery: Create a Search Index for fast needle-in-a-haystack log/JSON lookups
CREATE SEARCH INDEX idx_logs_trace_id
ON `observability.app_logs` (trace_id, log_payload);

-- Snowflake: Enable Search Optimization Service for selective point lookups
ALTER TABLE crm.customers ADD SEARCH OPTIMIZATION ON EQUALITY(email, phone_number);
```

**Scenario — Fixing a bad Spark join plan caused by stale table statistics:**
You ingest 500 rows into `dim_stores` via an external Parquet job, but Spark's metastore has no size stats for the table (`sizeInBytes = unknown` or stale). The optimizer assumes `dim_stores` is huge, chooses a **Sort-Merge Join** over a **Broadcast Join**, and triggers an unnecessary 200 GB shuffle on `fact_sales`. Running `ANALYZE TABLE dim_stores COMPUTE STATISTICS` immediately flips the plan to a sub-second Broadcast Join.

> [!WARNING]
> Traditional B-Tree indexes work great for selective OLTP lookups (`WHERE user_id = 123`), but maintaining B-Tree indexes on multi-terabyte append-only warehouse tables kills bulk `INSERT`/`MERGE` throughput. Cloud DWs therefore replace B-Trees with columnar **zone maps** (min/max ranges) and **bloom filters**.

> [!TIP]
> In Spark/Databricks, whenever you overwrite or append to external Parquet/Hive tables outside Delta Lake, re-run `ANALYZE TABLE ... COMPUTE STATISTICS` (or `REFRESH TABLE`) so the Cost-Based Optimizer (CBO) knows the true table size.

---

## 6. CTE Materialization Behavior Across Engines

A Common Table Expression (`WITH cte AS (...)`) improves readability, but engines differ sharply on whether a CTE is **inlined** (expanded like a macro into every place it is referenced) or **materialized** (computed once into a temporary buffer and reused).

If an expensive CTE containing a multi-table join is referenced 4 times in downstream `UNION ALL` branches and the engine **inlines** it, your expensive join executes **4 separate times**.

### CTE Materialization Behavior Matrix

| Engine | Default CTE Behavior | Can You Override? |
|---|---|---|
| **DuckDB** | Smart / cost-based: materializes if referenced multiple times (or via `MATERIALIZED`) | ✅ `AS MATERIALIZED (...)` / `AS NOT MATERIALIZED (...)` |
| **Snowflake** | Generally inlined; may auto-cache/reuse identical subplans when beneficial | ❌ No hint (use `CREATE TEMP TABLE` to force materialization) |
| **BigQuery** | **Always inlined** (re-evaluated per reference unless results cached) | ❌ No hint (use `CREATE TEMP TABLE` to force materialization) |
| **Databricks (Spark SQL)** | Inlined into the logical plan by Catalyst; repeated subtrees are NOT automatically reused unless cached | ✅ `CACHE TABLE` or persist/temp table |
| **PostgreSQL (v12+)** | Inlined if referenced once; materialized if referenced multiple times | ✅ `AS MATERIALIZED (...)` / `AS NOT MATERIALIZED (...)` |

```sql
-- Anti-Pattern in BigQuery / Spark: `base_orders` is referenced twice,
-- so the expensive 3-way join executes TWICE!
WITH base_orders AS (
    SELECT o.order_id, o.customer_id, o.amount, c.segment
    FROM fact_orders o
    JOIN dim_customers c ON o.customer_id = c.customer_id
    WHERE o.order_date >= DATE '2026-01-01'
)
SELECT 'high_value' AS bucket, COUNT(*) FROM base_orders WHERE amount > 500
UNION ALL
SELECT 'vip_segment' AS bucket, COUNT(*) FROM base_orders WHERE segment = 'VIP';
```

```sql
-- Fix 1 (BigQuery / Snowflake / Spark): Force materialization with a TEMP TABLE
CREATE TEMP TABLE tmp_base_orders AS
SELECT o.order_id, o.customer_id, o.amount, c.segment
FROM fact_orders o
JOIN dim_customers c ON o.customer_id = c.customer_id
WHERE o.order_date >= DATE '2026-01-01';

SELECT 'high_value' AS bucket, COUNT(*) FROM tmp_base_orders WHERE amount > 500
UNION ALL
SELECT 'vip_segment' AS bucket, COUNT(*) FROM tmp_base_orders WHERE segment = 'VIP';

-- Fix 2 (DuckDB / Postgres 12+): Explicit MATERIALIZED keyword
WITH base_orders AS MATERIALIZED (
    SELECT o.order_id, o.customer_id, o.amount, c.segment
    FROM fact_orders o
    JOIN dim_customers c ON o.customer_id = c.customer_id
    WHERE o.order_date >= DATE '2026-01-01'
)
SELECT 'high_value' AS bucket, COUNT(*) FROM base_orders WHERE amount > 500
UNION ALL
SELECT 'vip_segment' AS bucket, COUNT(*) FROM base_orders WHERE segment = 'VIP';
```

**Scenario — Cutting BigQuery slot & byte costs by 4x on a multi-metric funnel:**
An executive funnel script builds a `user_sessions` CTE joining 5 TB of events, then references `user_sessions` in 4 separate `UNION ALL` branches (one per funnel step). Because BigQuery inlines CTEs, the job scans 20 TB total. Replacing the CTE with `CREATE TEMP TABLE user_sessions AS ...` scans the 5 TB source **once** (or even better, rewriting the 4 `UNION ALL` branches into a single `COUNTIF(...)` pass over the CTE).

> [!WARNING]
> **Inlining is a double-edged sword.** Inlining helps when a CTE is referenced once with an outer filter (`SELECT * FROM cte WHERE id = 5`), because the filter gets pushed down into the scan. Conversely, materializing a CTE too early acts as an **optimization fence**, blocking predicate pushdown and forcing the engine to write every row before filtering.

> [!TIP]
> When a CTE is referenced **multiple times** across `UNION ALL` or self-joins in BigQuery, Snowflake, or Spark: either combine the branches into a single pass using conditional aggregation (`SUM(CASE WHEN ...)`), or materialize the intermediate result into a `TEMP TABLE`.

---

## Performance Tuning Checklist

Before shipping a production pipeline or dbt model, run through these five checks:

1. **Check Partition & Cluster Alignment:** Does your `WHERE` clause filter directly on the partition/cluster column without wrapping it in a function?
2. **Inspect the Execution Plan:** Are partitions pruned? Is `Spill to remote storage` equal to `0`? Are estimated rows close to actual rows?
3. **Eliminate Fan-Outs:** Are you joining two child tables at different grains without pre-aggregating?
4. **Watch for Skew & Repeated CTEs:** Are hot keys (`NULL`, `'UNKNOWN'`) causing straggler tasks? Are heavy CTEs referenced multiple times?
5. **Project Early, Join Small:** Did you drop unused columns (`SELECT col1, col2` instead of `SELECT *`) and aggregate facts before joining descriptive attributes?

---

*← Back: [Module 4 — Cloud Data Warehouse Nuance Matrix](04-cloud-dw-matrix.md)*
