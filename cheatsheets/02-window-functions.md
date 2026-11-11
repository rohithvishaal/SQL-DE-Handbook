# Module 2: Advanced Analytical SQL & Window Functions

> A Data Engineering focused reference covering ranking functions, value functions, window frames, CTEs, recursive queries, and filtering window results using dialect-agnostic ANSI SQL.

---

## Table of Contents

1. [Ranking Functions](#1-ranking-functions)
2. [Value Functions](#2-value-functions)
3. [Window Frames](#3-window-frames)
4. [CTEs & Modularity](#4-ctes--modularity)
5. [Filtering Window Results](#5-filtering-window-results)

---

## 1. Ranking Functions

### ROW_NUMBER()

`ROW_NUMBER()` assigns a unique sequential integer to each row within a partition, ordered by the specified columns. Ties receive **distinct** numbers — the assignment among ties is non-deterministic unless the `ORDER BY` is fully deterministic.

```sql
ROW_NUMBER() OVER (
    [PARTITION BY partition_col]
    ORDER BY sort_col [ASC | DESC]
)
```

**Data Engineering Example**

*`raw_events`*

| user_id | event_type | event_time          |
|---------|------------|---------------------|
| 101     | page_view  | 2024-01-15 08:00:00 |
| 101     | click      | 2024-01-15 08:05:00 |
| 101     | purchase   | 2024-01-15 08:30:00 |
| 102     | page_view  | 2024-01-15 09:00:00 |
| 102     | click      | 2024-01-15 09:10:00 |

```sql
-- Deduplicate: keep the latest event per user
SELECT *
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY event_time DESC
        ) AS rn
    FROM raw_events
) sub
WHERE rn = 1;
```

*Expected output:*

| user_id | event_type | event_time          | rn |
|---------|------------|---------------------|----|
| 101     | purchase   | 2024-01-15 08:30:00 | 1  |
| 102     | click      | 2024-01-15 09:10:00 | 1  |

> [!WARNING]
> **Gotcha:** If two rows have the same `ORDER BY` values, `ROW_NUMBER()` assigns them arbitrarily — different runs may assign different numbers. This makes dedup non-deterministic. Always include a tiebreaker column (e.g., a unique ID) in the `ORDER BY` to ensure reproducible results in data pipelines.

---

### RANK()

`RANK()` assigns a rank to each row within a partition, with **gaps** after ties. If two rows tie at rank 1, the next row gets rank 3 (not 2).

```sql
RANK() OVER (
    [PARTITION BY partition_col]
    ORDER BY sort_col [ASC | DESC]
)
```

**Data Engineering Example**

*`sales`*

| rep_id | region | revenue |
|--------|--------|---------|
| R1     | East   | 50000   |
| R2     | East   | 50000   |
| R3     | East   | 40000   |
| R4     | West   | 70000   |
| R5     | West   | 60000   |

```sql
SELECT
    rep_id,
    region,
    revenue,
    RANK() OVER (PARTITION BY region ORDER BY revenue DESC) AS rnk
FROM sales;
```

*Expected output:*

| rep_id | region | revenue | rnk |
|--------|--------|---------|-----|
| R1     | East   | 50000   | 1   |
| R2     | East   | 50000   | 1   |
| R3     | East   | 40000   | 3   |
| R4     | West   | 70000   | 1   |
| R5     | West   | 60000   | 2   |

> [!WARNING]
> **Gotcha:** `RANK()` produces gaps (`1, 1, 3`), which can break downstream logic that expects contiguous ranks (e.g., "get top-3" may return only 2 distinct rank values if there are ties). If you need gap-free ranks, use `DENSE_RANK()`. If you need exactly N rows, use `ROW_NUMBER()`.

---

### DENSE_RANK()

`DENSE_RANK()` assigns ranks with **no gaps** — ties share the same rank, and the next distinct value gets the next consecutive rank.

```sql
DENSE_RANK() OVER (
    [PARTITION BY partition_col]
    ORDER BY sort_col [ASC | DESC]
)
```

**Data Engineering Example**

```sql
SELECT
    rep_id,
    region,
    revenue,
    DENSE_RANK() OVER (PARTITION BY region ORDER BY revenue DESC) AS d_rank
FROM sales;
```

*Expected output:*

| rep_id | region | revenue | d_rank |
|--------|--------|---------|--------|
| R1     | East   | 50000   | 1      |
| R2     | East   | 50000   | 1      |
| R3     | East   | 40000   | 2      |
| R4     | West   | 70000   | 1      |
| R5     | West   | 60000   | 2      |

> [!WARNING]
> **Gotcha:** `DENSE_RANK() <= 3` returns the top-3 **distinct values**, which may include more than 3 rows if there are ties. If your pipeline must produce exactly 3 rows per partition, use `ROW_NUMBER() <= 3` with a deterministic tiebreaker.

---

### NTILE()

`NTILE(n)` divides the rows in each partition into `n` approximately equal groups (buckets), numbered 1 through `n`. If the rows don't divide evenly, earlier buckets get one extra row each.

```sql
NTILE(n) OVER (
    [PARTITION BY partition_col]
    ORDER BY sort_col
)
```

**Data Engineering Example**

*`customers`*

| customer_id | lifetime_value |
|-------------|----------------|
| C1          | 5000           |
| C2          | 12000          |
| C3          | 8000           |
| C4          | 1500           |
| C5          | 20000          |
| C6          | 3000           |

```sql
-- Segment customers into quartiles by lifetime value
SELECT
    customer_id,
    lifetime_value,
    NTILE(4) OVER (ORDER BY lifetime_value DESC) AS quartile
FROM customers;
```

*Expected output:*

| customer_id | lifetime_value | quartile |
|-------------|----------------|----------|
| C5          | 20000          | 1        |
| C2          | 12000          | 1        |
| C3          | 8000           | 2        |
| C1          | 5000           | 2        |
| C6          | 3000           | 3        |
| C4          | 1500           | 4        |

> [!WARNING]
> **Gotcha:** `NTILE` distributes rows by count, not by value range. With skewed data, bucket boundaries may be misleading — a "top quartile" might include values very close to the median. For value-based bucketing, use `WIDTH_BUCKET` or explicit `CASE WHEN` ranges. Also, with small datasets, some buckets may be empty or have only 1 row.

---

## 2. Value Functions

### LEAD() and LAG()

`LAG()` accesses a value from a **previous** row; `LEAD()` accesses a value from a **subsequent** row, based on the window's `ORDER BY`. They are essential for calculating deltas, detecting state changes, and sessionization.

```sql
LAG(column [, offset [, default]])  OVER (PARTITION BY ... ORDER BY ...)
LEAD(column [, offset [, default]]) OVER (PARTITION BY ... ORDER BY ...)
```

**Data Engineering Example**

*`daily_metrics`*

| metric_date | pipeline    | row_count |
|-------------|-------------|-----------|
| 2024-01-10  | etl_orders  | 15000     |
| 2024-01-11  | etl_orders  | 14200     |
| 2024-01-12  | etl_orders  | 16500     |
| 2024-01-13  | etl_orders  | 0         |

```sql
SELECT
    metric_date,
    pipeline,
    row_count,
    LAG(row_count, 1, 0) OVER (
        PARTITION BY pipeline ORDER BY metric_date
    ) AS prev_day_count,
    row_count - LAG(row_count, 1, 0) OVER (
        PARTITION BY pipeline ORDER BY metric_date
    ) AS day_over_day_change
FROM daily_metrics;
```

*Expected output:*

| metric_date | pipeline   | row_count | prev_day_count | day_over_day_change |
|-------------|------------|-----------|----------------|---------------------|
| 2024-01-10  | etl_orders | 15000     | 0              | 15000               |
| 2024-01-11  | etl_orders | 14200     | 15000          | -800                |
| 2024-01-12  | etl_orders | 16500     | 14200          | 2300                |
| 2024-01-13  | etl_orders | 0         | 16500          | -16500              |

> [!WARNING]
> **Gotcha:** Without a default value (3rd argument), `LAG`/`LEAD` return NULL for boundary rows. Arithmetic on NULLs propagates NULLs, so your day-over-day change becomes NULL for the first row instead of a usable number. Always specify a default or wrap with `COALESCE`.

---

### FIRST_VALUE() and LAST_VALUE()

`FIRST_VALUE()` returns the value from the first row of the window frame; `LAST_VALUE()` returns the value from the last row. These are useful for comparing every row against a reference point (e.g., earliest or latest value in a group).

```sql
FIRST_VALUE(column) OVER (
    PARTITION BY ... ORDER BY ...
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)

LAST_VALUE(column) OVER (
    PARTITION BY ... ORDER BY ...
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
```

**Data Engineering Example**

*`pipeline_runs`*

| run_id | pipeline   | started_at          | duration_sec |
|--------|------------|---------------------|--------------|
| 1      | etl_orders | 2024-01-10 02:00:00 | 120          |
| 2      | etl_orders | 2024-01-11 02:00:00 | 95           |
| 3      | etl_orders | 2024-01-12 02:00:00 | 200          |
| 4      | etl_orders | 2024-01-13 02:00:00 | 150          |

```sql
SELECT
    run_id,
    pipeline,
    duration_sec,
    FIRST_VALUE(duration_sec) OVER (
        PARTITION BY pipeline ORDER BY started_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_run_duration,
    LAST_VALUE(duration_sec) OVER (
        PARTITION BY pipeline ORDER BY started_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS latest_run_duration
FROM pipeline_runs;
```

*Expected output:*

| run_id | pipeline   | duration_sec | first_run_duration | latest_run_duration |
|--------|------------|--------------|--------------------|---------------------|
| 1      | etl_orders | 120          | 120                | 150                 |
| 2      | etl_orders | 95           | 120                | 150                 |
| 3      | etl_orders | 200          | 120                | 150                 |
| 4      | etl_orders | 150          | 120                | 150                 |

> [!WARNING]
> **Gotcha:** `LAST_VALUE()` with the **default** window frame (`ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`) returns the current row's value, not the actual last row of the partition. You almost always need to specify `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` to get the true last value. This is the most common window function bug.

---

### NTH_VALUE()

`NTH_VALUE(column, n)` returns the value from the *n*-th row of the window frame. It is useful for grabbing specific positional values (e.g., 2nd highest, 3rd event) without subqueries.

```sql
NTH_VALUE(column, n) OVER (
    PARTITION BY ... ORDER BY ...
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
```

**Data Engineering Example**

```sql
-- Get the 2nd fastest pipeline run duration per pipeline
SELECT
    run_id,
    pipeline,
    duration_sec,
    NTH_VALUE(duration_sec, 2) OVER (
        PARTITION BY pipeline ORDER BY duration_sec ASC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS second_fastest
FROM pipeline_runs;
```

*Expected output:*

| run_id | pipeline   | duration_sec | second_fastest |
|--------|------------|--------------|----------------|
| 2      | etl_orders | 95           | 120            |
| 1      | etl_orders | 120          | 120            |
| 4      | etl_orders | 150          | 120            |
| 3      | etl_orders | 200          | 120            |

> [!WARNING]
> **Gotcha:** If the partition has fewer than `n` rows, `NTH_VALUE` returns NULL. Also, like `LAST_VALUE`, the default frame (`UNBOUNDED PRECEDING TO CURRENT ROW`) may cause `NTH_VALUE` to return NULL for early rows where the *n*-th row hasn't been reached yet. Always specify the full frame: `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`.

---

## 3. Window Frames

### ROWS BETWEEN vs RANGE BETWEEN

Window frames define the subset of rows that each window function computation operates on. `ROWS` counts **physical rows**; `RANGE` considers **logical value ranges**. Understanding the difference is critical for correct running totals, moving averages, and time-window calculations.

```sql
-- ROWS: physical position-based
function() OVER (
    ORDER BY col
    ROWS BETWEEN <start> AND <end>
)

-- RANGE: logical value-based
function() OVER (
    ORDER BY col
    RANGE BETWEEN <start> AND <end>
)

-- Frame boundary options:
--   UNBOUNDED PRECEDING    (first row of partition)
--   n PRECEDING            (n rows/values before current)
--   CURRENT ROW
--   n FOLLOWING             (n rows/values after current)
--   UNBOUNDED FOLLOWING     (last row of partition)
```

**Key Differences**

| Aspect        | `ROWS BETWEEN`                      | `RANGE BETWEEN`                          |
|---------------|--------------------------------------|------------------------------------------|
| Counting      | Physical row positions               | Logical value proximity                  |
| Ties           | Each tied row gets its own frame     | All tied rows share the same frame       |
| Default frame  | N/A                                  | `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` (the default when only `ORDER BY` is specified) |
| Numeric offset | Counts rows: `3 PRECEDING` = 3 rows | Counts values: `3 PRECEDING` = values within ±3 of current |

**Data Engineering Example**

*`daily_revenue`*

| day        | revenue |
|------------|---------|
| 2024-01-01 | 100     |
| 2024-01-02 | 200     |
| 2024-01-02 | 150     |
| 2024-01-03 | 300     |

```sql
-- ROWS: running sum based on physical row position
SELECT
    day,
    revenue,
    SUM(revenue) OVER (
        ORDER BY day
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_sum_rows
FROM daily_revenue;
```

*Expected output:*

| day        | revenue | running_sum_rows |
|------------|---------|------------------|
| 2024-01-01 | 100     | 100              |
| 2024-01-02 | 200     | 300              |
| 2024-01-02 | 150     | 450              |
| 2024-01-03 | 300     | 750              |

```sql
-- RANGE: running sum groups ties together
SELECT
    day,
    revenue,
    SUM(revenue) OVER (
        ORDER BY day
        RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_sum_range
FROM daily_revenue;
```

*Expected output (note: both Jan-02 rows show 450):*

| day        | revenue | running_sum_range |
|------------|---------|-------------------|
| 2024-01-01 | 100     | 100               |
| 2024-01-02 | 200     | 450               |
| 2024-01-02 | 150     | 450               |
| 2024-01-03 | 300     | 750               |

> [!WARNING]
> **Gotcha:** The default frame when you only specify `ORDER BY` (without an explicit `ROWS`/`RANGE` clause) is `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. This means ties are grouped, which silently inflates running sums. Always specify `ROWS BETWEEN` explicitly for predictable results.

<ClozeDrill
  card-id="diag-m2-rows-range"
  module-id="m2"
  prompt="Recall the explicit physical frame clause so tied timestamps increment sequentially instead of grouping:"
  :prefix="'SELECT day, revenue,\n  SUM(revenue) OVER (\n    ORDER BY day\n    '"
  answer="ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW"
  :suffix="'\n  ) AS running_sum_rows\nFROM daily_revenue;'"
/>

---

### Running Sums

A running (cumulative) sum adds each row's value to the total of all preceding rows. It is a fundamental pattern for building cumulative metrics in data warehouses.

```sql
SUM(measure) OVER (
    [PARTITION BY group_col]
    ORDER BY sort_col
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
)
```

**Data Engineering Example**

*`daily_signups`*

| signup_date | channel  | signups |
|-------------|----------|---------|
| 2024-01-01  | organic  | 50      |
| 2024-01-02  | organic  | 75      |
| 2024-01-03  | organic  | 60      |
| 2024-01-01  | paid     | 30      |
| 2024-01-02  | paid     | 45      |
| 2024-01-03  | paid     | 55      |

```sql
SELECT
    signup_date,
    channel,
    signups,
    SUM(signups) OVER (
        PARTITION BY channel
        ORDER BY signup_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_signups
FROM daily_signups;
```

*Expected output:*

| signup_date | channel | signups | cumulative_signups |
|-------------|---------|---------|-------------------|
| 2024-01-01  | organic | 50      | 50                |
| 2024-01-02  | organic | 75      | 125               |
| 2024-01-03  | organic | 60      | 185               |
| 2024-01-01  | paid    | 30      | 30                |
| 2024-01-02  | paid    | 45      | 75                |
| 2024-01-03  | paid    | 55      | 130               |

> [!WARNING]
> **Gotcha:** Running sums with `RANGE` (the default) and duplicate `ORDER BY` values produce identical cumulative values for tied rows — which may be incorrect if each row represents a distinct transaction. Always use `ROWS` for running sums on transactional data.

---

### Moving Averages

A moving (rolling) average smooths noisy time-series data by averaging over a fixed-size window of recent rows. It is commonly used for trend detection in pipeline monitoring dashboards.

```sql
AVG(measure) OVER (
    [PARTITION BY group_col]
    ORDER BY sort_col
    ROWS BETWEEN n PRECEDING AND CURRENT ROW
)
```

**Data Engineering Example**

*`daily_latency`*

| report_date | pipeline   | avg_latency_ms |
|-------------|------------|----------------|
| 2024-01-01  | etl_orders | 120            |
| 2024-01-02  | etl_orders | 150            |
| 2024-01-03  | etl_orders | 130            |
| 2024-01-04  | etl_orders | 500            |
| 2024-01-05  | etl_orders | 140            |

```sql
-- 3-day moving average to smooth out spikes
SELECT
    report_date,
    pipeline,
    avg_latency_ms,
    ROUND(AVG(avg_latency_ms) OVER (
        PARTITION BY pipeline
        ORDER BY report_date
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 1) AS moving_avg_3d
FROM daily_latency;
```

*Expected output:*

| report_date | pipeline   | avg_latency_ms | moving_avg_3d |
|-------------|------------|----------------|---------------|
| 2024-01-01  | etl_orders | 120            | 120.0         |
| 2024-01-02  | etl_orders | 150            | 135.0         |
| 2024-01-03  | etl_orders | 130            | 133.3         |
| 2024-01-04  | etl_orders | 500            | 260.0         |
| 2024-01-05  | etl_orders | 140            | 256.7         |

> [!WARNING]
> **Gotcha:** For the first `n-1` rows, the window contains fewer rows than specified (a "partial window"). The average is still computed but over fewer data points, which can be misleading. Consider filtering these partial-window rows out, or use `COUNT(*) OVER (...)` alongside to flag them.

---

### Sliding Time Windows

For time-based windows (e.g., "sum of revenue in the last 7 days"), `RANGE` with an interval offset is more correct than `ROWS` because `ROWS` counts physical rows and misses gaps in the time series.

```sql
-- Engines that support interval-based RANGE (PostgreSQL, Snowflake, etc.)
SUM(measure) OVER (
    ORDER BY date_col
    RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
)
```

**Data Engineering Example**

*`transactions`*

| txn_date   | amount |
|------------|--------|
| 2024-01-01 | 100    |
| 2024-01-03 | 200    |
| 2024-01-08 | 150    |
| 2024-01-09 | 300    |

```sql
-- 7-day rolling revenue (handles date gaps correctly)
SELECT
    txn_date,
    amount,
    SUM(amount) OVER (
        ORDER BY txn_date
        RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
    ) AS rolling_7d_revenue
FROM transactions;
```

*Expected output:*

| txn_date   | amount | rolling_7d_revenue |
|------------|--------|--------------------|
| 2024-01-01 | 100    | 100                |
| 2024-01-03 | 200    | 300                |
| 2024-01-08 | 150    | 450                |
| 2024-01-09 | 300    | 650                |

> [!WARNING]
> **Gotcha:** Not all engines support `RANGE` with interval offsets — MySQL and older SQL Server versions do not. As a workaround, join against a date spine or use a correlated subquery. Also, `RANGE` with intervals requires the `ORDER BY` column to be a date/timestamp type — numeric columns won't work with `INTERVAL`.

---

## 4. CTEs & Modularity

### Common Table Expressions (CTEs)

A CTE (Common Table Expression) is a named temporary result set defined within a `WITH` clause. It exists only for the duration of the query and improves readability by breaking complex logic into named, composable steps — analogous to variables in code.

```sql
WITH cte_name AS (
    SELECT ...
    FROM ...
    WHERE ...
)
SELECT *
FROM cte_name;
```

**Data Engineering Example**

*`raw_events`*

| user_id | event_type | event_time          |
|---------|------------|---------------------|
| 101     | click      | 2024-01-15 08:00:00 |
| 101     | purchase   | 2024-01-15 08:30:00 |
| 102     | page_view  | 2024-01-15 09:00:00 |
| 103     | click      | NULL                |
| 101     | click      | 2024-01-16 10:00:00 |

```sql
-- Step-by-step transformation pipeline in a single query
WITH raw AS (
    SELECT
        user_id,
        event_type,
        CAST(event_time AS TIMESTAMP) AS event_ts
    FROM raw_events
    WHERE event_time IS NOT NULL
),

daily_agg AS (
    SELECT
        user_id,
        CAST(event_ts AS DATE) AS event_date,
        COUNT(*) AS event_count
    FROM raw
    GROUP BY user_id, CAST(event_ts AS DATE)
)

SELECT
    event_date,
    COUNT(DISTINCT user_id) AS dau,
    SUM(event_count) AS total_events
FROM daily_agg
GROUP BY event_date
ORDER BY event_date;
```

*Expected output:*

| event_date | dau | total_events |
|------------|-----|--------------|
| 2024-01-15 | 2   | 3            |
| 2024-01-16 | 1   | 1            |

> [!WARNING]
> **Gotcha:** CTEs are **not** materialized in most engines — they are inlined like views, so a CTE referenced multiple times may be executed multiple times. If performance matters, consider creating a temp table instead. Snowflake and BigQuery do auto-materialize in some cases, but don't rely on it.

---

### Chaining CTEs

Multiple CTEs can be chained in a single `WITH` clause, separated by commas. Each CTE can reference any CTE defined before it, enabling pipeline-style transformations within a single statement.

```sql
WITH step_1 AS (
    SELECT ... FROM source
),
step_2 AS (
    SELECT ... FROM step_1 WHERE ...
),
step_3 AS (
    SELECT ... FROM step_2 JOIN other_table ON ...
)
SELECT * FROM step_3;
```

**Data Engineering Example**

*`raw_orders`*

| order_id | customer_id | amount | order_date |
|----------|-------------|--------|------------|
| 1001     | 501         | 600.00 | 2024-01-10 |
| 1002     | 501         | 650.00 | 2024-01-10 |
| 1003     | 501         | 250.00 | 2024-01-12 |
| 1004     | 502         | 400.00 | 2024-01-11 |
| NULL     | 502         | 900.00 | 2024-01-12 |

```sql
WITH stg_orders AS (
    -- Stage 1: Clean and type raw data
    SELECT
        CAST(order_id AS BIGINT) AS order_id,
        CAST(customer_id AS BIGINT) AS customer_id,
        CAST(amount AS DECIMAL(12,2)) AS amount,
        CAST(order_date AS DATE) AS order_date
    FROM raw_orders
    WHERE order_id IS NOT NULL
),

order_daily AS (
    -- Stage 2: Aggregate to daily grain
    SELECT
        customer_id,
        order_date,
        SUM(amount) AS daily_spend,
        COUNT(*) AS order_count
    FROM stg_orders
    GROUP BY customer_id, order_date
),

customer_summary AS (
    -- Stage 3: Roll up to customer level
    SELECT
        customer_id,
        SUM(daily_spend) AS total_spend,
        SUM(order_count) AS total_orders,
        MIN(order_date) AS first_order,
        MAX(order_date) AS last_order
    FROM order_daily
    GROUP BY customer_id
)

SELECT *
FROM customer_summary
WHERE total_spend > 1000
ORDER BY total_spend DESC;
```

*Expected output:*

| customer_id | total_spend | total_orders | first_order | last_order |
|-------------|-------------|--------------|-------------|------------|
| 501         | 1500.00     | 3            | 2024-01-10  | 2024-01-12 |

> [!WARNING]
> **Gotcha:** Chained CTEs can become hard to debug because intermediate results are not visible. Add `SELECT * FROM step_n` at the end temporarily during development to inspect each stage. In dbt, prefer separate models over long CTE chains for better testability and lineage.

---

### Recursive CTEs

A recursive CTE references itself to iteratively build a result set. It is the standard SQL way to traverse hierarchies (org charts, category trees, bill of materials) and graphs (paths, dependencies).

```sql
WITH RECURSIVE cte_name AS (
    -- Anchor member: the starting point
    SELECT columns
    FROM base_table
    WHERE start_condition

    UNION ALL

    -- Recursive member: references the CTE itself
    SELECT columns
    FROM base_table AS t
    INNER JOIN cte_name AS c
        ON t.parent_key = c.child_key
)
SELECT * FROM cte_name;
```

> [!NOTE]
> Some engines (SQL Server, Snowflake) omit the `RECURSIVE` keyword — the CTE is implicitly recursive when it references itself.

**Data Engineering Example — Org Chart Traversal**

*`employees`*

| emp_id | name    | manager_id |
|--------|---------|------------|
| 1      | Alice   | NULL       |
| 2      | Bob     | 1          |
| 3      | Charlie | 1          |
| 4      | Diana   | 2          |
| 5      | Eve     | 2          |
| 6      | Frank   | 3          |

```sql
WITH RECURSIVE org_tree AS (
    -- Anchor: start from the CEO (no manager)
    SELECT
        emp_id,
        name,
        manager_id,
        0 AS depth,
        CAST(name AS VARCHAR(500)) AS path
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    -- Recursive: find direct reports of current level
    SELECT
        e.emp_id,
        e.name,
        e.manager_id,
        ot.depth + 1,
        CAST(ot.path || ' > ' || e.name AS VARCHAR(500))
    FROM employees AS e
    INNER JOIN org_tree AS ot
        ON e.manager_id = ot.emp_id
)
SELECT emp_id, name, depth, path
FROM org_tree
ORDER BY path;
```

*Expected output:*

| emp_id | name    | depth | path                  |
|--------|---------|-------|-----------------------|
| 1      | Alice   | 0     | Alice                 |
| 2      | Bob     | 1     | Alice > Bob           |
| 4      | Diana   | 2     | Alice > Bob > Diana   |
| 5      | Eve     | 2     | Alice > Bob > Eve     |
| 3      | Charlie | 1     | Alice > Charlie       |
| 6      | Frank   | 2     | Alice > Charlie > Frank|

> [!WARNING]
> **Gotcha:** Recursive CTEs can enter **infinite loops** if the data contains cycles (e.g., A → B → A). Always add a safety limit: `WHERE depth < 100` in the recursive member, or use engine-specific guards like `MAXRECURSION` (SQL Server) or `max_recursion` (Snowflake). Also, recursive CTEs can be very slow on large graphs — consider materializing adjacency lists or using a closure table pattern for production.

---

**Example — Graph Traversal (Data Lineage)**

*`data_lineage`*

| source_table | target_table |
|--------------|--------------|
| raw_events   | stg_events   |
| stg_events   | fct_sessions |
| raw_users    | stg_users    |
| stg_users    | fct_sessions |
| fct_sessions | rpt_daily    |

```sql
-- Find all upstream dependencies of rpt_daily
WITH RECURSIVE upstream AS (
    SELECT source_table, target_table, 1 AS hops
    FROM data_lineage
    WHERE target_table = 'rpt_daily'

    UNION ALL

    SELECT dl.source_table, dl.target_table, u.hops + 1
    FROM data_lineage AS dl
    INNER JOIN upstream AS u
        ON dl.target_table = u.source_table
    WHERE u.hops < 10  -- safety limit
)
SELECT DISTINCT source_table, hops
FROM upstream
ORDER BY hops;
```

*Expected output:*

| source_table | hops |
|--------------|------|
| fct_sessions | 1    |
| stg_events   | 2    |
| stg_users    | 2    |
| raw_events   | 3    |
| raw_users    | 3    |

> [!WARNING]
> **Gotcha:** The `DISTINCT` in the final `SELECT` is important — without it, the same table may appear multiple times via different paths. In production data lineage systems, prefer a dedicated graph database or a pre-materialized closure table over recursive CTEs for performance.

---

## 5. Filtering Window Results

### Subquery Approach

Window functions cannot be used in `WHERE` or `HAVING` clauses because they are evaluated **after** `WHERE` and `GROUP BY`. To filter on a window function result, wrap the windowed query in a subquery (or CTE) and filter in the outer query.

```sql
SELECT *
FROM (
    SELECT
        columns,
        WINDOW_FUNC() OVER (...) AS wf_result
    FROM table_name
) sub
WHERE wf_result = desired_value;
```

**Data Engineering Example**

*`raw_events`*

| user_id | event_type | event_time          |
|---------|------------|---------------------|
| 101     | page_view  | 2024-01-15 08:00:00 |
| 101     | purchase   | 2024-01-15 08:30:00 |
| 102     | page_view  | 2024-01-15 09:00:00 |
| 102     | click      | 2024-01-15 09:10:00 |

```sql
-- Get the most recent event per user
WITH ranked AS (
    SELECT
        user_id,
        event_type,
        event_time,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY event_time DESC
        ) AS rn
    FROM raw_events
)
SELECT user_id, event_type, event_time
FROM ranked
WHERE rn = 1;
```

*Expected output:*

| user_id | event_type | event_time          |
|---------|------------|---------------------|
| 101     | purchase   | 2024-01-15 08:30:00 |
| 102     | click      | 2024-01-15 09:10:00 |

> [!WARNING]
> **Gotcha:** The subquery/CTE approach adds a layer of nesting. Some engines do not push predicates into the subquery, meaning the window function is computed for **all** rows before filtering. On very large tables, this can be expensive. Check your query plan and consider pre-filtering in the inner query's `WHERE` clause.

---

### QUALIFY

`QUALIFY` is a dedicated clause for filtering on window function results **without** needing a subquery. It is evaluated after `SELECT` and window functions, making queries cleaner and more concise.

```sql
SELECT columns,
       WINDOW_FUNC() OVER (...) AS wf_result
FROM table_name
QUALIFY wf_result = desired_value;
```

**Data Engineering Example**

*Source table:* `raw_events` (same as above)

```sql
-- Same dedup, but cleaner with QUALIFY
SELECT
    user_id,
    event_type,
    event_time
FROM raw_events
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_id
    ORDER BY event_time DESC
) = 1;
```

*Expected output:*

| user_id | event_type | event_time          |
|---------|------------|---------------------|
| 101     | purchase   | 2024-01-15 08:30:00 |
| 102     | click      | 2024-01-15 09:10:00 |

> [!WARNING]
> **Gotcha:** `QUALIFY` is **not** ANSI SQL. It is supported by Snowflake, BigQuery, Databricks, and DuckDB — but **not** by PostgreSQL, MySQL, SQL Server, or Redshift. For portable SQL, stick with the subquery/CTE approach. Always document which dialect a query targets if your team uses `QUALIFY`.

---

### SQL Logical Order of Operations (Reference)

Understanding the logical evaluation order is essential for knowing which clause can reference what:

```
1. FROM / JOIN        ← tables and join conditions
2. WHERE              ← row-level pre-filter
3. GROUP BY           ← grouping
4. HAVING             ← aggregate filter
5. SELECT             ← column expressions & window functions
6. QUALIFY            ← window function filter (non-ANSI)
7. DISTINCT           ← deduplication
8. ORDER BY           ← sorting
9. LIMIT / OFFSET     ← pagination
```

> [!WARNING]
> **Gotcha:** Because `SELECT` aliases are created at step 5, they cannot be used in `WHERE` (step 2) or `HAVING` (step 4) in strict ANSI SQL. They *can* be used in `QUALIFY` (step 6) and `ORDER BY` (step 8). Some engines relax this rule — know your engine's behavior.

---

*End of Module 2*
