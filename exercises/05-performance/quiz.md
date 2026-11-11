# Module 5 Quiz: Query Performance, Optimization & Anti-Patterns

> Diagnose slow execution plans, identify SQL anti-patterns, eliminate data skew, and rewrite queries for optimal cloud warehouse performance.

---

## Question 1: Diagnosing an Execution Plan (`EXPLAIN ANALYZE` / Query Profile)

A nightly financial pipeline takes 52 minutes instead of its usual 3 minutes. You open the execution plan and inspect the runtime metrics:

```text
Node 1: TableScan (fact_orders)       | Partitions Pruned: 0 / 730 | Rows Out: 120M
Node 2: TableScan (dim_promotions)    | Partitions Pruned: 0 / 1   | Rows Out: 50K
Node 3: HashJoin (on promo_code)      | Rows In: 120M + 50K      | Rows Out: 1.8B
Node 4: WindowSort (PARTITION BY id)  | Memory Used: 16 GB       | Spill to Remote Storage: 64 GB
```

**Task:**
1. Identify **three** distinct bottlenecks revealed by this execution plan.
2. Which single bug at **Node 3** directly caused **Node 4** to spill 64 GB to remote storage?

---

## Question 2: Non-SARGable Predicate Defeating Partition Pruning

The table `analytics.fact_sessions` (18 TB) is partitioned by `DATE(session_start_ts)` and clustered by `country_code`. An analyst writes this query for a daily dashboard:

```sql
SELECT *
FROM analytics.fact_sessions
WHERE TO_CHAR(session_start_ts, 'YYYY-MM') = '2026-02'
  AND LOWER(country_code) = 'us';
```

**Task:**
1. Identify **all three** performance anti-patterns in this query.
2. Rewrite the query so it enables partition pruning, cluster pruning, and columnar projection.

---

## Question 3: Physical Data Layout & the "Small Files Problem"

A data engineer creates a Delta Lake table in Databricks to store IoT sensor telemetry (500 million rows/day):

```sql
CREATE TABLE bronze.iot_telemetry (
    device_id   STRING,
    event_ts    TIMESTAMP,
    sensor_type STRING,
    reading     DOUBLE
)
USING DELTA
PARTITIONED BY (device_id, event_ts);
```

After 3 days, basic queries fail with out-of-memory errors on the driver node during metadata listing, and storage contains 18 million tiny 4 KB Parquet files.

**Task:**
1. Explain why this `PARTITIONED BY` clause caused the "small files problem."
2. Rewrite the DDL using best-practice physical layout for **Databricks (Delta Lake)** and **Google BigQuery**, assuming queries typically filter by date range and `device_id`.

---

## Question 4: Silent Fan-Out & Band-Aid `SELECT DISTINCT`

A revenue report is supposed to show each `order_id`, its total amount paid, and total shipping weight. A developer joins `orders` directly to `order_payments` (an order can have split payments: gift card + credit card) and `order_items` (an order can have multiple items), then adds `SELECT DISTINCT` after noticing duplicate rows:

```sql
SELECT DISTINCT
    o.order_id,
    o.customer_id,
    SUM(p.paid_amount)  AS total_paid,
    SUM(i.weight_grams) AS total_weight
FROM orders o
LEFT JOIN order_payments p ON o.order_id = p.order_id
LEFT JOIN order_items    i ON o.order_id = i.order_id
GROUP BY o.order_id, o.customer_id;
```

**Task:**
1. If order `#9001` has **2 payments** ($30 + $70) and **3 items** (200g + 300g + 500g), what wrong values does this query return for `total_paid` and `total_weight`? Does `SELECT DISTINCT` fix the math?
2. Rewrite the query to produce exact metrics without fan-out.

---

## Question 5: Eliminating Data Skew via Key Salting

A Spark SQL job joins a 10-billion-row `clickstream_events` table to a 50-million-row `dim_users` table on `user_id`. Every night, 99 of 100 tasks finish in 45 seconds, while **Task #100 runs for 55 minutes and crashes with an Executor OOM**.

Inspection reveals that **35% of all clickstream rows** have `user_id = 'GUEST_CHECKOUT'` (mapped to a single synthetic row in `dim_users`).

**Task:**
1. Why does a standard Hash Join or Sort-Merge Join stall on a single task?
2. Write the SQL using a **10-bucket Key Salting** pattern to distribute `'GUEST_CHECKOUT'` evenly across 10 workers without distorting normal `user_id` rows.

---

## Question 6: Implicit Type Conversion & Over-Grouping

Examine the following slow query joining `fact_transactions` (`merchant_id` is `BIGINT`, 2 billion rows) with `dim_merchants` (`merchant_id` is `VARCHAR`, 100K rows):

```sql
SELECT
    m.merchant_id,
    m.merchant_name,
    m.category,
    m.country,
    m.account_owner,
    m.onboarding_date,
    SUM(t.amount) AS gmv
FROM fact_transactions t
JOIN dim_merchants m
  ON t.merchant_id = m.merchant_id
GROUP BY
    m.merchant_id,
    m.merchant_name,
    m.category,
    m.country,
    m.account_owner,
    m.onboarding_date;
```

Occasionally, this pipeline also crashes mid-run with `Numeric value 'PENDING_REVIEW' is not recognized`.

**Task:**
1. Explain why the query crashes intermittently and why the join disables zone-map pruning on `fact_transactions`.
2. Identify the **over-grouping** anti-pattern and rewrite the query fixing both issues.

---

## Question 7: CTE Materialization Trap in Cloud Warehouses

In **BigQuery**, a marketing engineer builds a 4-channel attribution report using a heavy CTE that joins 8 TB of ad impressions with user sessions:

```sql
WITH attributed_sessions AS (
    SELECT
        s.session_id,
        s.user_id,
        i.channel,
        s.revenue
    FROM raw.sessions s          -- 5 TB
    JOIN raw.ad_impressions i    -- 3 TB
      ON s.user_id = i.user_id
     AND s.session_ts BETWEEN i.impression_ts AND TIMESTAMP_ADD(i.impression_ts, INTERVAL 7 DAY)
    WHERE s.session_date >= '2026-01-01'
)
SELECT 'paid_search' AS report_slice, SUM(revenue) AS rev FROM attributed_sessions WHERE channel = 'SEM'
UNION ALL
SELECT 'social'      AS report_slice, SUM(revenue) AS rev FROM attributed_sessions WHERE channel = 'SOCIAL'
UNION ALL
SELECT 'display'     AS report_slice, SUM(revenue) AS rev FROM attributed_sessions WHERE channel = 'DISPLAY'
UNION ALL
SELECT 'all_paid'    AS report_slice, SUM(revenue) AS rev FROM attributed_sessions WHERE channel IN ('SEM', 'SOCIAL', 'DISPLAY');
```

Instead of scanning 8 TB, BigQuery bills **32 TB**!

**Task:**
1. Why did BigQuery scan 32 TB instead of 8 TB?
2. Rewrite this query using **two different valid approaches** (one pure single-query SQL optimization, one explicit materialization approach) so the base tables are scanned only **once** (≤ 8 TB).

---

## Question 8: Stale Table Statistics & Join Strategy Selection

After loading 25,000 rows into a new external Parquet dimension table `dim_currency_rates` (total size: 1.5 MB) in Databricks, you join it to a 4 TB `fact_ledger` table. Looking at the Spark UI, Spark chose a **Sort-Merge Join** instead of a **Broadcast Join**, triggering a massive 4 TB shuffle across the cluster.

**Task:**
1. Why did the Cost-Based Optimizer (CBO) choose a Sort-Merge Join for a 1.5 MB table?
2. Give **two** ways to fix this (one metadata/statistics command, and one SQL optimizer hint).

---

*Open the **Solution & Explanation** tab on any card above to check the worked performance diagnoses and rewrites.*
