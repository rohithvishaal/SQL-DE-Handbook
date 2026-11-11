# Module 4 Solutions: Cloud Data Warehouse Nuance Matrix

> Full solutions and dialect explanations for the [Module 4 Quiz](quiz.md).

---

## Solution 1: Window Filtering (`QUALIFY`) Migration

### 1. Platform Support
- **BigQuery:** ✅ Runs natively.
- **DuckDB:** ✅ Runs natively.
- **Databricks (Spark SQL):** ❌ Fails with a syntax error — Spark SQL does **not** support the `QUALIFY` clause.

### 2. Databricks (Spark SQL) Rewrite
Wrap the window function inside a CTE or subquery and filter in an outer `WHERE` clause:

```sql
WITH ranked_customers AS (
    SELECT
        customer_id,
        email,
        updated_at,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY updated_at DESC
        ) AS rn
    FROM bronze.raw_customers
)
SELECT
    customer_id,
    email,
    updated_at
FROM ranked_customers
WHERE rn = 1;
```

> [!TIP]
> When maintaining a multi-engine codebase (or dbt macros targeting Databricks), always use the CTE + `WHERE rn = 1` pattern — it is 100% portable across ANSI/DuckDB, Snowflake, BigQuery, and Databricks.

---

## Solution 2: JSON Extraction Syntax Per Platform

### Platform Mapping
- **Snippet A:** **DuckDB** (`->` extracts JSON, `->>` extracts unquoted text)
- **Snippet B:** **BigQuery** — **and this is the broken/buggy snippet!**
- **Snippet C:** **Snowflake** (colon `:` notation on `VARIANT` + `::STRING` cast)
- **Snippet D:** **Databricks (Spark SQL)** (`GET_JSON_OBJECT(col, '$.path')` returning `STRING`)

### Why Snippet B Has a Subtle Bug
In BigQuery, `JSON_EXTRACT()` returns a **JSON-formatted value** (meaning scalar strings stay wrapped in double quotes like `"iOS"`), whereas `JSON_EXTRACT_SCALAR()` extracts the **unquoted scalar string** (`iOS`). Mixing `JSON_EXTRACT` for `device_os` causes downstream filters like `WHERE device_os = 'iOS'` to silently fail!

**Fixed BigQuery SQL:**
```sql
SELECT
    JSON_EXTRACT_SCALAR(payload, '$.event_id')   AS event_id,
    JSON_EXTRACT_SCALAR(payload, '$.device.os')  AS device_os,
    JSON_EXTRACT_SCALAR(payload, '$.items[0]')   AS first_item
FROM raw_events;
```

> [!WARNING]
> In BigQuery, `JSON_EXTRACT_SCALAR` returns `NULL` if the target path points to an object `{...}` or array `[...]`. Use `JSON_EXTRACT` (or `JSON_QUERY`) for nested objects/arrays and `JSON_EXTRACT_SCALAR` (or `JSON_VALUE`) for leaf scalar values.

---

## Solution 3: Array Flattening Without Dropping Records

### 1. Why 65% of Orders Vanished
`LATERAL VIEW EXPLODE(...)` behaves like an **INNER JOIN** between the parent row and the array elements. Whenever `discount_codes` is `NULL` or `[]` (empty array), `EXPLODE` produces **0 rows**, silently dropping the entire parent order from the result set.

### 2. Preserving `NULL` and Empty Arrays Across Platforms

**Databricks (Spark SQL):** Use `EXPLODE_OUTER`:
```sql
SELECT
    o.order_id,
    code
FROM orders o
LATERAL VIEW EXPLODE_OUTER(o.discount_codes) t AS code;
```

**Snowflake:** Pass `OUTER => TRUE` to `LATERAL FLATTEN`:
```sql
SELECT
    o.order_id,
    f.VALUE::STRING AS code
FROM orders o,
     LATERAL FLATTEN(input => o.discount_codes, OUTER => TRUE) f;
```

**BigQuery:** Use an explicit `LEFT JOIN UNNEST(...)`:
```sql
SELECT
    o.order_id,
    code
FROM orders o
LEFT JOIN UNNEST(o.discount_codes) AS code;
```

> [!WARNING]
> In BigQuery, comma syntax (`FROM orders o, UNNEST(o.discount_codes) AS code`) is an implicit `CROSS JOIN`, which drops empty/NULL arrays just like `EXPLODE`. Always write `LEFT JOIN UNNEST(...)` when parent rows must survive.

---

## Solution 4: `MERGE INTO` With Hard-Delete Propagation

### 1. `WHEN NOT MATCHED BY SOURCE` Support
- **BigQuery:** ✅ Supported natively.
- **Databricks (Spark SQL / Delta):** ✅ Supported natively.
- **DuckDB:** ✅ Supported natively in DuckDB 1.4+ (and PostgreSQL 17+; note earlier ANSI baselines lacked it).
- **Snowflake:** ❌ Not supported in standard `MERGE INTO` (you must stage deletes or run a separate `DELETE` statement).

### 2. Databricks Table Format Requirement
`dim_accounts` **must be a Delta Lake table** (`USING DELTA`). `MERGE INTO` will fail on plain Parquet, CSV, or JSON Hive tables in Spark SQL.

### 3. Snowflake Duplicate Source Key Behavior
In Snowflake, if `staging_accounts` contains **two or more matching rows** for the same `account_id` that match a single target row in `dim_accounts`, Snowflake throws a non-deterministic merge error (`Duplicate row detected during DML action`) — or if `ERROR_ON_NONDETERMINISTIC_MERGE = FALSE`, picks one arbitrary row nondeterministically.

> [!TIP]
> Always deduplicate your staging CTE inside `MERGE` using `QUALIFY ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY updated_at DESC) = 1` before joining to the target table.

---

## Solution 5: Safe Division & Downstream `AVG()` Trap

### Which Query Is Most Accurate?
**Options B (`DIV0NULL`), C (`SAFE_DIVIDE`), and D (`NULLIF`)** produce the most accurate weekly `AVG(conv_rate)`!

### Option A vs. Option B in Snowflake
- **Option A (`DIV0(conversions, clicks)`):** Returns **`0`** when `clicks = 0`. When you later compute `AVG(conv_rate)` across days or campaigns, those zero-click campaigns get averaged in as `0%` conversion rate, artificially dragging down the true average.
- **Option B (`DIV0NULL(conversions, clicks)`):** Returns **`NULL`** when `clicks = 0`. Standard SQL aggregates (`AVG`, `MIN`, `MAX`) ignore `NULL`s, so zero-traffic campaigns do not distort the average.

```sql
-- Portable across DuckDB, Snowflake, BigQuery, and Databricks:
SELECT
    campaign_id,
    AVG(conversions * 1.0 / NULLIF(clicks, 0)) AS avg_conv_rate
FROM campaigns
GROUP BY campaign_id;
```

> [!TIP]
> Multiply the numerator by `1.0` (or cast to `FLOAT`/`DOUBLE`) when both columns are integers in engines like DuckDB or Postgres, so integer division doesn't truncate `3 / 4` to `0`.

---

## Solution 6: String Aggregation Across Dialects

### 1. Snowflake (`LISTAGG`)
```sql
SELECT
    ticket_id,
    LISTAGG(DISTINCT tag_name, ', ') WITHIN GROUP (ORDER BY tag_name) AS tags
FROM support_ticket_tags
GROUP BY ticket_id;
```

### 2. BigQuery (`STRING_AGG`)
```sql
SELECT
    ticket_id,
    STRING_AGG(DISTINCT tag_name, ', ' ORDER BY tag_name) AS tags
FROM support_ticket_tags
GROUP BY ticket_id;
```

### 3. Databricks / Spark SQL (`COLLECT_SET` + `SORT_ARRAY` + `CONCAT_WS`)
```sql
SELECT
    ticket_id,
    CONCAT_WS(', ', SORT_ARRAY(COLLECT_SET(tag_name))) AS tags
FROM support_ticket_tags
GROUP BY ticket_id;
```

> [!WARNING]
> Do not confuse `COLLECT_LIST` with `COLLECT_SET` in Spark SQL: `COLLECT_LIST` preserves duplicates, whereas `COLLECT_SET` deduplicates. Neither guarantees alphabetical order on its own, so wrap the result in `SORT_ARRAY(...)` before calling `CONCAT_WS`.

---

## Solution 7: Date Truncation & Date Arithmetic Pitfalls

### 1. The Three BigQuery Incompatibilities
1. **`DATE_TRUNC` argument order is reversed:** Snowflake takes `DATE_TRUNC('MONTH', order_ts)`, whereas BigQuery expects `DATE_TRUNC(order_ts, MONTH)` (expression first, unquoted date part second).
2. **`DATEADD` does not exist in BigQuery:** BigQuery uses `DATE_ADD(expr, INTERVAL N DAY)` (or `TIMESTAMP_ADD` if `order_ts` is a `TIMESTAMP`).
3. **`DATEDIFF` signature differs:** BigQuery uses `DATE_DIFF(end_date, start_date, DAY)` (or `TIMESTAMP_DIFF`) — note the underscore AND reversed start/end argument order (`end - start` vs Snowflake's `DATEDIFF('DAY', start, end)`)!

### 2. Rewritten Queries

**BigQuery (assuming `TIMESTAMP` columns):**
```sql
SELECT
    DATE_TRUNC(order_ts, MONTH)                    AS order_month,
    TIMESTAMP_ADD(order_ts, INTERVAL 30 DAY)       AS due_date,
    TIMESTAMP_DIFF(shipped_ts, created_ts, DAY)    AS fulfillment_days
FROM orders;
```
*(If the columns are `DATE` instead of `TIMESTAMP`, use `DATE_ADD(order_dt, INTERVAL 30 DAY)` and `DATE_DIFF(shipped_dt, created_dt, DAY)`.)*

**DuckDB:**
```sql
SELECT
    DATE_TRUNC('month', order_ts)                       AS order_month,
    order_ts + INTERVAL '30' DAY                        AS due_date,
    DATE_DIFF('day', created_ts, shipped_ts)            AS fulfillment_days
FROM orders;
```

> [!WARNING]
> **Watch the sign of `DATE_DIFF` vs `DATEDIFF`!** Snowflake's `DATEDIFF('DAY', start, end)` returns a positive number when `end > start`. BigQuery's `DATE_DIFF(end, start, DAY)` puts `end` **first** — swapping them silently negates all your fulfillment durations.

---

## Solution 8: Mergeable HyperLogLog Sketches & Clustering

### 1. Why You Cannot Sum Daily `APPROX_COUNT_DISTINCT` Counts
Distinct user counts are **non-additive**. If `user_123` visits on Monday, Tuesday, and Wednesday, summing daily unique counts counts `user_123` **3 times** instead of **1 time**.

HyperLogLog (HLL) sketches store probabilistic bit-registers rather than an integer count, making them **losslessly mergeable** across arbitrary time windows without double-counting returning users.

### 2. BigQuery Implementation

**Step 1: Create the partitioned & clustered daily HLL sketch table**
```sql
CREATE TABLE `analytics.daily_user_hll`
PARTITION BY event_date
CLUSTER BY platform
AS
SELECT
    DATE(event_ts)           AS event_date,
    platform,
    HLL_COUNT.INIT(user_id)  AS user_hll_sketch
FROM `raw.clickstream`
GROUP BY 1, 2;
```

**Step 2: Merge sketches for any 30-day rolling window**
```sql
SELECT
    platform,
    HLL_COUNT.MERGE(user_hll_sketch) AS unique_users_30d
FROM `analytics.daily_user_hll`
WHERE event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY platform;
```

> [!TIP]
> Pre-aggregating HLL sketches into a partitioned & clustered summary table turns multi-terabyte `COUNT(DISTINCT)` dashboard queries into sub-second lookups that scan only kilobytes of sketch bytes.

---

*← Back to [Module 4 Quiz](quiz.md) | Next: [Module 5 Quiz →](../05-performance/quiz.md)*
