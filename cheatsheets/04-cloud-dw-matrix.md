# Module 4: Cloud Data Warehouse Nuance Matrix

> A comprehensive side-by-side comparison of SQL behavior and syntax across **ANSI/DuckDB**, **Snowflake**, **Google BigQuery**, and **Databricks (Spark SQL)**.

---

## Table of Contents

1. [Window Filtering (QUALIFY)](#1-window-filtering-qualify)
2. [JSON Extraction](#2-json-extraction)
3. [Array Flattening](#3-array-flattening-unnest-vs-flatten-vs-explode)
4. [Upsert / MERGE INTO](#4-upsert--merge-into)
5. [Safe Division](#5-safe-division)
6. [String Aggregation](#6-string-aggregation)
7. [Date/Time Functions & Timestamp Handling](#7-datetime-functions--timestamp-handling)
8. [DDL Differences](#8-ddl-differences)
9. [Data Types Mapping](#9-data-types-mapping-across-platforms)
10. [Semi-Structured Data Handling](#10-semi-structured-data-handling)
11. [Approximate Aggregations](#11-approximate-aggregations)
12. [Materialized Views & Clustering](#12-materialized-views--clustering)

---

## 1. Window Filtering (QUALIFY)

`QUALIFY` filters the result of window functions the same way `HAVING` filters aggregations. It eliminates the need for a wrapping subquery just to reference a window function in a predicate.

Not all engines support `QUALIFY` natively — those that don't require a CTE or subquery workaround.

| Feature | ANSI / DuckDB | Snowflake | BigQuery | Databricks (Spark SQL) |
|---|---|---|---|---|
| Native `QUALIFY` | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No (use subquery) |

### ANSI / DuckDB

```sql
SELECT
    customer_id,
    order_date,
    amount,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) AS rn
FROM orders
QUALIFY rn = 1;
```

### Snowflake

```sql
SELECT
    customer_id,
    order_date,
    amount
FROM orders
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) = 1;
```

### BigQuery

```sql
SELECT
    customer_id,
    order_date,
    amount
FROM orders
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) = 1;
```

### Databricks (Spark SQL)

```sql
-- No QUALIFY — use a subquery / CTE
WITH ranked AS (
    SELECT
        customer_id,
        order_date,
        amount,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) AS rn
    FROM orders
)
SELECT customer_id, order_date, amount
FROM ranked
WHERE rn = 1;
```

> [!WARNING]
> Databricks / Spark SQL does **not** support `QUALIFY`. Always wrap in a CTE. Forgetting this is one of the most frequent migration bugs when porting Snowflake or BigQuery SQL to Databricks.

> [!TIP]
> Even in engines that support `QUALIFY`, you can reference the window alias **or** repeat the window expression. Using an alias keeps the query readable.

**Scenario — Deduplicating CDC customer snapshots to keep only the latest record per ID:**

```sql
-- Snowflake / BigQuery / DuckDB: single-query CDC deduplication
SELECT customer_id, email, plan_tier, cdc_updated_at
FROM raw.cdc_customers
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY cdc_updated_at DESC) = 1;
```

---

## 2. JSON Extraction

Modern data warehouses all support querying JSON/semi-structured data, but the syntax varies dramatically. Understanding these differences is critical for data engineers who work with event streams, API responses, and nested payloads.

| Operation | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Extract text value | `json ->> 'key'` | `col:key::STRING` or `GET_PATH(col, 'key')` | `JSON_EXTRACT_SCALAR(col, '$.key')` | `col:key` or `GET_JSON_OBJECT(col, '$.key')` |
| Extract object | `json -> 'key'` | `col:key` | `JSON_EXTRACT(col, '$.key')` | `col:key` |
| Nested access | `json -> 'a' ->> 'b'` | `col:a.b::STRING` | `JSON_EXTRACT_SCALAR(col, '$.a.b')` | `GET_JSON_OBJECT(col, '$.a.b')` |
| Array element | `json -> 'arr' ->> 0` | `col:arr[0]::STRING` | `JSON_EXTRACT_SCALAR(col, '$.arr[0]')` | `GET_JSON_OBJECT(col, '$.arr[0]')` |

### ANSI / DuckDB

```sql
-- DuckDB uses the -> (JSON) and ->> (text) operators
SELECT
    event_payload ->> 'user_id'                  AS user_id,
    event_payload -> 'device' ->> 'os'           AS device_os,
    event_payload -> 'items' ->> 0               AS first_item
FROM raw_events;
```

### Snowflake

```sql
-- Snowflake uses colon notation on VARIANT columns
SELECT
    event_payload:user_id::STRING                 AS user_id,
    event_payload:device.os::STRING               AS device_os,
    event_payload:items[0]::STRING                AS first_item
FROM raw_events;
```

### BigQuery

```sql
-- BigQuery uses JSON_EXTRACT / JSON_EXTRACT_SCALAR with JSONPath
SELECT
    JSON_EXTRACT_SCALAR(event_payload, '$.user_id')           AS user_id,
    JSON_EXTRACT_SCALAR(event_payload, '$.device.os')         AS device_os,
    JSON_EXTRACT_SCALAR(event_payload, '$.items[0]')          AS first_item
FROM raw_events;
```

### Databricks (Spark SQL)

```sql
-- Databricks supports colon notation on STRING columns (DBR 13+)
-- or the classic GET_JSON_OBJECT function
SELECT
    GET_JSON_OBJECT(event_payload, '$.user_id')               AS user_id,
    GET_JSON_OBJECT(event_payload, '$.device.os')             AS device_os,
    GET_JSON_OBJECT(event_payload, '$.items[0]')              AS first_item
FROM raw_events;

-- Colon notation (when column is STRING type):
SELECT event_payload:user_id AS user_id FROM raw_events;
```

> [!WARNING]
> Snowflake's colon notation works only on `VARIANT` columns, not raw `VARCHAR` JSON. Parse with `PARSE_JSON()` first if your source column is a string.

> [!TIP]
> In BigQuery, prefer `JSON_EXTRACT_SCALAR` for leaf values (returns `STRING`) and `JSON_EXTRACT` for nested objects (returns `JSON`). Using the wrong one leads to silent `NULL` results.

**Scenario — Extracting nested event properties from a Kafka topic landing table:**

```sql
-- Snowflake: parse raw JSON string into VARIANT, then extract
SELECT
    PARSE_JSON(raw_json):event_name::STRING  AS event_name,
    PARSE_JSON(raw_json):properties.amount::FLOAT AS amount
FROM bronze.kafka_events
WHERE PARSE_JSON(raw_json):event_name::STRING = 'purchase';
```

---

## 3. Array Flattening (UNNEST vs FLATTEN vs EXPLODE)

Flattening arrays — turning each array element into its own row — is one of the most common semi-structured data operations in data engineering. Every platform has a different function name and syntax for this.

| Operation | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Flatten array | `UNNEST(arr)` | `LATERAL FLATTEN(input => col)` | `UNNEST(arr)` | `EXPLODE(arr)` |
| Preserve NULLs / empties | `UNNEST(arr) WITH ORDINALITY` | `FLATTEN(..., OUTER => TRUE)` | `LEFT JOIN UNNEST(arr)` | `EXPLODE_OUTER(arr)` |
| With index | `UNNEST(arr) WITH ORDINALITY` | `f.INDEX` | `WITH OFFSET` | `POSEXPLODE(arr)` |

### ANSI / DuckDB

```sql
-- Simple unnest
SELECT
    order_id,
    item.value AS line_item
FROM orders, UNNEST(line_items) AS item(value);

-- With index (ordinality)
SELECT
    order_id,
    idx,
    item
FROM orders, UNNEST(line_items) WITH ORDINALITY AS t(item, idx);
```

### Snowflake

```sql
-- LATERAL FLATTEN
SELECT
    o.order_id,
    f.VALUE::STRING AS line_item,
    f.INDEX         AS item_index
FROM orders o,
     LATERAL FLATTEN(input => o.line_items) f;

-- OUTER => TRUE preserves rows where the array is NULL or empty
SELECT
    o.order_id,
    f.VALUE::STRING AS line_item
FROM orders o,
     LATERAL FLATTEN(input => o.line_items, OUTER => TRUE) f;
```

<DialectBlock
  engine="snowflake"
  card-id="diag-m4-snowflake-flatten"
  module-id="m4"
  cloze-prompt="Recall how Snowflake preserves rows whose flattened array is NULL or empty:"
  :cloze-prefix="'SELECT o.order_id, f.VALUE::STRING AS line_item\nFROM orders o,\n     LATERAL '"
  cloze-answer="FLATTEN(input => o.line_items, OUTER => TRUE)"
  cloze-suffix=" f;"
/>

### BigQuery

```sql
-- UNNEST in FROM clause (CROSS JOIN is implicit)
SELECT
    order_id,
    line_item
FROM orders,
     UNNEST(line_items) AS line_item;

-- With offset and preserving empty arrays
SELECT
    order_id,
    line_item,
    idx
FROM orders
LEFT JOIN UNNEST(line_items) AS line_item WITH OFFSET AS idx
    ON TRUE;
```

### Databricks (Spark SQL)

```sql
-- EXPLODE generates one row per array element
SELECT
    order_id,
    line_item
FROM orders
LATERAL VIEW EXPLODE(line_items) t AS line_item;

-- POSEXPLODE includes position index
SELECT
    order_id,
    pos,
    line_item
FROM orders
LATERAL VIEW POSEXPLODE(line_items) t AS pos, line_item;

-- EXPLODE_OUTER keeps rows with NULL/empty arrays
SELECT
    order_id,
    line_item
FROM orders
LATERAL VIEW EXPLODE_OUTER(line_items) t AS line_item;
```

<DialectBlock
  engine="databricks"
  card-id="m4-db-explode-outer"
  module-id="m4"
  cloze-prompt="Recall Spark SQL syntax to explode an array without dropping NULL or empty arrays:"
  :cloze-prefix="'SELECT order_id, line_item\nFROM orders\n'"
  cloze-answer="LATERAL VIEW EXPLODE_OUTER(line_items) t AS line_item"
  cloze-suffix=";"
/>

> [!WARNING]
> Default `UNNEST`/`EXPLODE`/`FLATTEN` will **drop rows** where the array is `NULL` or empty. In data engineering pipelines this can silently lose records. Always use the OUTER variant (`OUTER => TRUE`, `LEFT JOIN UNNEST`, `EXPLODE_OUTER`) if you need to preserve those rows.

> [!TIP]
> In Snowflake, `LATERAL FLATTEN` can also flatten objects (key-value pairs) with `f.KEY` and `f.VALUE`. Combine with `RECURSIVE => TRUE` to flatten deeply nested structures.

**Scenario — Expanding order line items from an API webhook payload while preserving orders with no items:**

```sql
-- BigQuery: LEFT JOIN UNNEST preserves orders with empty/NULL item arrays
SELECT
    o.order_id,
    o.order_ts,
    item.sku,
    item.qty
FROM raw.webhook_orders o
LEFT JOIN UNNEST(o.line_items) AS item;
```

---

## 4. Upsert / MERGE INTO

`MERGE INTO` is the SQL standard way to perform upserts — insert new rows or update existing ones based on a join condition. All four platforms support it, but with syntax quirks. This is the backbone of SCD Type 1 updates and incremental loads.

| Feature | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| `MERGE INTO` | ✅ | ✅ | ✅ | ✅ (Delta Lake) |
| Multi-clause match | ✅ | ✅ | ✅ | ✅ |
| `WHEN NOT MATCHED BY SOURCE` | ✅ (DuckDB 1.4+) | ❌ | ✅ | ✅ |
| Must be Delta/managed table | No | No | No | Yes (Delta) |

### ANSI / DuckDB

```sql
MERGE INTO dim_customer AS tgt
USING staging_customer AS src
ON tgt.customer_id = src.customer_id
WHEN MATCHED THEN
    UPDATE SET
        name       = src.name,
        email      = src.email,
        updated_at = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, email, created_at, updated_at)
    VALUES (src.customer_id, src.name, src.email, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
```

### Snowflake

```sql
MERGE INTO dim_customer AS tgt
USING staging_customer AS src
ON tgt.customer_id = src.customer_id
WHEN MATCHED AND src.updated_at > tgt.updated_at THEN
    UPDATE SET
        tgt.name       = src.name,
        tgt.email      = src.email,
        tgt.updated_at = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, email, created_at, updated_at)
    VALUES (src.customer_id, src.name, src.email, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
```

### BigQuery

```sql
MERGE INTO `project.dataset.dim_customer` AS tgt
USING `project.dataset.staging_customer` AS src
ON tgt.customer_id = src.customer_id
WHEN MATCHED THEN
    UPDATE SET
        tgt.name       = src.name,
        tgt.email      = src.email,
        tgt.updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, email, created_at, updated_at)
    VALUES (src.customer_id, src.name, src.email, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP())
WHEN NOT MATCHED BY SOURCE THEN
    DELETE;  -- BigQuery supports this clause
```

### Databricks (Spark SQL)

```sql
-- Target must be a Delta table
MERGE INTO dim_customer AS tgt
USING staging_customer AS src
ON tgt.customer_id = src.customer_id
WHEN MATCHED AND src.updated_at > tgt.updated_at THEN
    UPDATE SET *
WHEN NOT MATCHED THEN
    INSERT *
WHEN NOT MATCHED BY SOURCE THEN
    DELETE;
```

> [!WARNING]
> In Databricks, `MERGE INTO` only works on **Delta tables**. Attempting to merge into a Parquet or CSV table will fail. In Snowflake, duplicate matches in the source cause a non-deterministic error — always deduplicate your staging table first.

> [!TIP]
> BigQuery and Databricks support `WHEN NOT MATCHED BY SOURCE` to detect deletes. Use this to implement hard-delete propagation in your incremental models.

**Scenario — Daily incremental upsert from a staging table loaded by Fivetran:**

```sql
-- Snowflake: Deduplicate staging first, then merge
WITH deduped_staging AS (
    SELECT *
    FROM staging_customer
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY _fivetran_synced DESC) = 1
)
MERGE INTO dim_customer AS tgt
USING deduped_staging AS src
ON tgt.customer_id = src.customer_id
WHEN MATCHED THEN UPDATE SET name = src.name, email = src.email
WHEN NOT MATCHED THEN INSERT (customer_id, name, email) VALUES (src.customer_id, src.name, src.email);
```

---

## 5. Safe Division

Dividing by zero returns an error in most SQL engines. In data engineering, division by zero is common (e.g., calculating rates where the denominator is zero). Each platform handles this differently.

| Approach | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Built-in safe divide | ❌ | `DIV0(a, b)` or `DIV0NULL(a, b)` | `SAFE_DIVIDE(a, b)` | ❌ |
| `NULLIF` pattern | ✅ | ✅ | ✅ | ✅ |
| `CASE` pattern | ✅ | ✅ | ✅ | ✅ |
| Div-by-zero behavior | Error | Error | Error | Returns `NULL` (sometimes) |

### Universal NULLIF Pattern (works everywhere)

```sql
-- Returns NULL when denominator is 0
SELECT
    region,
    total_revenue / NULLIF(total_orders, 0) AS avg_order_value
FROM regional_summary;
```

### Snowflake

```sql
-- DIV0: returns 0 when denominator is 0
SELECT region, DIV0(total_revenue, total_orders) AS avg_order_value
FROM regional_summary;

-- DIV0NULL: returns NULL when denominator is 0
SELECT region, DIV0NULL(total_revenue, total_orders) AS avg_order_value
FROM regional_summary;
```

### BigQuery

```sql
-- SAFE_DIVIDE: returns NULL when denominator is 0
SELECT
    region,
    SAFE_DIVIDE(total_revenue, total_orders) AS avg_order_value
FROM `project.dataset.regional_summary`;
```

<DialectBlock
  engine="bigquery"
  card-id="m4-bq-safe-divide"
  module-id="m4"
  cloze-prompt="Recall BigQuery's zero-safe division function returning NULL when denominator is 0:"
  :cloze-prefix="'SELECT region,\n  '"
  cloze-answer="SAFE_DIVIDE(total_revenue, total_orders)"
  :cloze-suffix="' AS avg_order_value\nFROM `project.dataset.regional_summary`;'"
/>

### Databricks (Spark SQL)

```sql
-- Spark SQL: use TRY_DIVIDE (DBR 14+) or NULLIF pattern
SELECT
    region,
    TRY_DIVIDE(total_revenue, total_orders) AS avg_order_value
FROM regional_summary;

-- Fallback: NULLIF
SELECT
    region,
    total_revenue / NULLIF(total_orders, 0) AS avg_order_value
FROM regional_summary;
```

> [!WARNING]
> Do **not** rely on engine-specific behavior for division by zero. Snowflake errors on `x / 0`, BigQuery errors on `x / 0`, and Spark SQL behavior has changed across versions. Always explicitly handle it.

> [!TIP]
> Use `NULLIF(denominator, 0)` as the universal, portable pattern. It works on every platform and returns `NULL` (not zero), making downstream aggregations (AVG, SUM) behave correctly by skipping NULLs.

**Scenario — Computing ad campaign click-through rate (CTR) safely for zero-impression days:**

```sql
-- Portable across all four engines: avoids ZeroDivisionError and returns NULL for AVG()
SELECT
    campaign_date,
    campaign_id,
    clicks * 1.0 / NULLIF(impressions, 0) AS ctr
FROM mart.daily_ad_metrics;
```

---

## 6. String Aggregation

Concatenating values from multiple rows into a single delimited string is essential for generating comma-separated lists, tag aggregations, and debug output. Every platform has a different function name.

| Function | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Aggregate concat | `STRING_AGG(col, ',')` | `LISTAGG(col, ',')` | `STRING_AGG(col, ',')` | `COLLECT_LIST(col)` + `CONCAT_WS` |
| With ordering | `STRING_AGG(col, ',' ORDER BY col)` | `LISTAGG(col, ',') WITHIN GROUP (ORDER BY col)` | `STRING_AGG(col, ',' ORDER BY col)` | Requires subquery |
| Distinct values | `STRING_AGG(DISTINCT col, ',')` | `LISTAGG(DISTINCT col, ',')` | `STRING_AGG(DISTINCT col, ',')` | `COLLECT_SET(col)` + `CONCAT_WS` |

### ANSI / DuckDB

```sql
SELECT
    department,
    STRING_AGG(employee_name, ', ' ORDER BY employee_name) AS team_members
FROM employees
GROUP BY department;
```

### Snowflake

```sql
SELECT
    department,
    LISTAGG(employee_name, ', ') WITHIN GROUP (ORDER BY employee_name) AS team_members
FROM employees
GROUP BY department;

-- With DISTINCT
SELECT
    department,
    LISTAGG(DISTINCT employee_name, ', ') WITHIN GROUP (ORDER BY employee_name) AS team_members
FROM employees
GROUP BY department;
```

### BigQuery

```sql
SELECT
    department,
    STRING_AGG(employee_name, ', ' ORDER BY employee_name) AS team_members
FROM employees
GROUP BY department;

-- With DISTINCT
SELECT
    department,
    STRING_AGG(DISTINCT employee_name, ', ' ORDER BY employee_name) AS team_members
FROM employees
GROUP BY department;
```

### Databricks (Spark SQL)

```sql
-- Spark SQL uses COLLECT_LIST + CONCAT_WS
SELECT
    department,
    CONCAT_WS(', ', SORT_ARRAY(COLLECT_LIST(employee_name))) AS team_members
FROM employees
GROUP BY department;

-- For distinct values, use COLLECT_SET (returns unique, unordered)
SELECT
    department,
    CONCAT_WS(', ', SORT_ARRAY(COLLECT_SET(employee_name))) AS team_members
FROM employees
GROUP BY department;
```

> [!WARNING]
> Snowflake's `LISTAGG` has a 16 MB result limit per group. In BigQuery, `STRING_AGG` has no hard limit but very large results can cause query failures. Always consider whether your concatenated list could explode in size.

> [!TIP]
> In Databricks, `COLLECT_LIST` retains duplicates and `COLLECT_SET` deduplicates. Wrap either in `SORT_ARRAY()` if you need deterministic ordering.

**Scenario — Rolling up unique product categories purchased per customer into a CRM tag list:**

```sql
-- Snowflake: deterministic, deduplicated category string per customer
SELECT
    customer_id,
    LISTAGG(DISTINCT category_name, ' | ') WITHIN GROUP (ORDER BY category_name) AS purchased_categories
FROM mart.order_items
GROUP BY customer_id;
```

---

## 7. Date/Time Functions & Timestamp Handling

Date and time handling is where cloud data warehouses diverge the most. Function names, default precision, timezone behavior, and date arithmetic syntax all differ. Getting these right is critical for data pipelines that span time zones.

### Current Timestamp

| Function | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Current timestamp | `CURRENT_TIMESTAMP` | `CURRENT_TIMESTAMP()` or `SYSDATE()` | `CURRENT_TIMESTAMP()` | `CURRENT_TIMESTAMP()` |
| Current date | `CURRENT_DATE` | `CURRENT_DATE` | `CURRENT_DATE()` | `CURRENT_DATE()` |
| UTC now | `CURRENT_TIMESTAMP AT TIME ZONE 'UTC'` | `SYSDATE()` (always UTC) | `CURRENT_TIMESTAMP()` (always UTC) | `CURRENT_TIMESTAMP()` (always UTC) |

### Date Truncation

| Function | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Truncate to month | `DATE_TRUNC('month', dt)` | `DATE_TRUNC('MONTH', dt)` | `DATE_TRUNC(dt, MONTH)` | `DATE_TRUNC('MONTH', dt)` |
| Truncate to week | `DATE_TRUNC('week', dt)` | `DATE_TRUNC('WEEK', dt)` | `DATE_TRUNC(dt, WEEK)` | `DATE_TRUNC('WEEK', dt)` |

> [!WARNING]
> **BigQuery reverses the argument order**: `DATE_TRUNC(date_expr, part)` vs everyone else's `DATE_TRUNC('part', date_expr)`. This is one of the most common migration bugs.

### Date Arithmetic

| Operation | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Add days | `dt + INTERVAL '7' DAY` | `DATEADD('DAY', 7, dt)` or `dt + 7` | `DATE_ADD(dt, INTERVAL 7 DAY)` | `DATE_ADD(dt, 7)` |
| Subtract dates (days) | `dt1 - dt2` | `DATEDIFF('DAY', dt2, dt1)` | `DATE_DIFF(dt1, dt2, DAY)` | `DATEDIFF(dt1, dt2)` |
| Add months | `dt + INTERVAL '3' MONTH` | `DATEADD('MONTH', 3, dt)` | `DATE_ADD(dt, INTERVAL 3 MONTH)` | `ADD_MONTHS(dt, 3)` |

### Date Formatting / Parsing

| Operation | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Format date | `STRFTIME(dt, '%Y-%m-%d')` | `TO_CHAR(dt, 'YYYY-MM-DD')` | `FORMAT_DATE('%Y-%m-%d', dt)` | `DATE_FORMAT(dt, 'yyyy-MM-dd')` |
| Parse string to date | `STRPTIME(str, '%Y-%m-%d')` | `TO_DATE(str, 'YYYY-MM-DD')` | `PARSE_DATE('%Y-%m-%d', str)` | `TO_DATE(str, 'yyyy-MM-dd')` |
| Extract part | `EXTRACT(YEAR FROM dt)` | `EXTRACT(YEAR FROM dt)` or `YEAR(dt)` | `EXTRACT(YEAR FROM dt)` | `EXTRACT(YEAR FROM dt)` or `YEAR(dt)` |

**Scenario — Building a daily revenue report with timezone conversion:**

```sql
-- Snowflake
SELECT
    DATE_TRUNC('DAY', CONVERT_TIMEZONE('UTC', 'America/New_York', event_ts)) AS report_date,
    SUM(amount) AS daily_revenue
FROM transactions
GROUP BY 1;

-- BigQuery
SELECT
    DATE_TRUNC(DATE(event_ts, 'America/New_York'), DAY) AS report_date,
    SUM(amount) AS daily_revenue
FROM transactions
GROUP BY 1;
```

> [!TIP]
> Always store timestamps in UTC in your data warehouse. Convert to local time only at the presentation layer or in final reporting views.

---

## 8. DDL Differences

Data Definition Language syntax — `CREATE TABLE`, `CREATE TABLE AS SELECT (CTAS)`, and external tables — differs across platforms in meaningful ways for data engineers building pipelines and managing schemas.

### CREATE TABLE

| Feature | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Basic syntax | `CREATE TABLE t (...)` | `CREATE TABLE t (...)` | `CREATE TABLE dataset.t (...)` | `CREATE TABLE t (...) USING DELTA` |
| If not exists | `CREATE TABLE IF NOT EXISTS` | `CREATE TABLE IF NOT EXISTS` | `CREATE TABLE IF NOT EXISTS` | `CREATE TABLE IF NOT EXISTS` |
| Temporary table | `CREATE TEMP TABLE t (...)` | `CREATE TEMPORARY TABLE t (...)` | `CREATE TEMP TABLE dataset.t (...)` | `CREATE TEMPORARY VIEW t AS ...` |
| Table comments | `COMMENT ON TABLE t IS '...'` | `COMMENT ON TABLE t IS '...'` | `OPTIONS(description='...')` | `COMMENT ON TABLE t IS '...'` |

### CTAS (CREATE TABLE AS SELECT)

```sql
-- ANSI / DuckDB
CREATE TABLE summary AS
SELECT region, SUM(revenue) AS total_rev
FROM sales
GROUP BY region;

-- Snowflake
CREATE TABLE summary AS
SELECT region, SUM(revenue) AS total_rev
FROM sales
GROUP BY region;

-- BigQuery
CREATE TABLE `project.dataset.summary` AS
SELECT region, SUM(revenue) AS total_rev
FROM `project.dataset.sales`
GROUP BY region;

-- Databricks
CREATE TABLE summary
USING DELTA
AS SELECT region, SUM(revenue) AS total_rev
FROM sales
GROUP BY region;
```

### External Tables

| Feature | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Syntax | `CREATE TABLE t AS SELECT * FROM read_parquet('s3://...')` | `CREATE EXTERNAL TABLE t (...) WITH LOCATION = @stage/path FILE_FORMAT = (TYPE = 'PARQUET')` | `CREATE EXTERNAL TABLE dataset.t OPTIONS (format='PARQUET', uris=['gs://...'])` | `CREATE TABLE t USING PARQUET LOCATION 's3://...'` |
| Supported formats | Parquet, CSV, JSON, etc. | Parquet, CSV, JSON, ORC, Avro | Parquet, CSV, JSON, ORC, Avro, Sheets | Parquet, CSV, JSON, ORC, Avro, Delta |

```sql
-- Snowflake: External table from S3 stage
CREATE OR REPLACE EXTERNAL TABLE raw.ext_events
    WITH LOCATION = @s3_landing_stage/events/
    FILE_FORMAT = (TYPE = 'PARQUET')
    AUTO_REFRESH = TRUE;

-- BigQuery: External table from GCS
CREATE EXTERNAL TABLE `project.dataset.ext_events`
OPTIONS (
    format = 'PARQUET',
    uris = ['gs://my-bucket/events/*.parquet']
);

-- Databricks: External table from S3
CREATE TABLE raw.ext_events
USING PARQUET
LOCATION 's3://my-bucket/events/';
```

> [!WARNING]
> BigQuery external tables do **not** support DML (INSERT, UPDATE, DELETE). They are read-only views over cloud storage. Use `CREATE TABLE ... AS SELECT` to materialize them if you need DML.

> [!TIP]
> In Snowflake, prefer `AUTO_REFRESH = TRUE` on external tables backed by S3/GCS event notifications for near-real-time data availability without manual refreshes.

**Scenario — Creating a zero-copy external staging table over raw Parquet event logs before loading Silver:**

```sql
-- DuckDB: query S3 Parquet directly and materialize into a managed table
CREATE TABLE bronze.events_snapshot AS
SELECT *
FROM read_parquet('s3://data-lake-landing/events/2026/03/*.parquet');
```

---

## 9. Data Types Mapping Across Platforms

Understanding data type equivalences is essential when migrating schemas or writing cross-platform SQL.

| Concept | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Integer (64-bit) | `BIGINT` | `NUMBER(38,0)` or `INTEGER` | `INT64` | `BIGINT` or `LONG` |
| Integer (32-bit) | `INTEGER` | `NUMBER(38,0)` | `INT64` (no 32-bit) | `INT` |
| Decimal/Numeric | `DECIMAL(p,s)` | `NUMBER(p,s)` | `NUMERIC(p,s)` or `BIGNUMERIC` | `DECIMAL(p,s)` |
| Float (64-bit) | `DOUBLE` | `FLOAT` or `DOUBLE` | `FLOAT64` | `DOUBLE` |
| Boolean | `BOOLEAN` | `BOOLEAN` | `BOOL` | `BOOLEAN` |
| String | `VARCHAR` | `VARCHAR` (max 16 MB) | `STRING` (unlimited) | `STRING` |
| Date | `DATE` | `DATE` | `DATE` | `DATE` |
| Timestamp (no TZ) | `TIMESTAMP` | `TIMESTAMP_NTZ` | `DATETIME` | `TIMESTAMP_NTZ` |
| Timestamp (with TZ) | `TIMESTAMPTZ` | `TIMESTAMP_TZ` | `TIMESTAMP` | `TIMESTAMP` |
| Binary | `BLOB` | `BINARY` | `BYTES` | `BINARY` |
| Array | `LIST` / `ARRAY` | `ARRAY` (VARIANT) | `ARRAY<T>` | `ARRAY<T>` |
| JSON / Semi-structured | `JSON` | `VARIANT` | `JSON` or `STRING` | `STRING` (with `:` syntax) |
| Map / Object | `MAP` / `STRUCT` | `OBJECT` (VARIANT) | `STRUCT<...>` | `MAP<K,V>` / `STRUCT<...>` |

> [!WARNING]
> BigQuery has **no** small integer types — everything is `INT64`. Snowflake's `NUMBER` defaults to `NUMBER(38,0)` (integer). When migrating, watch for precision loss when mapping `FLOAT` to `NUMBER`.

> [!TIP]
> BigQuery's `TIMESTAMP` is always UTC. If you need a "local" timestamp without timezone, use `DATETIME`. This distinction does not exist the same way in Snowflake (which has `TIMESTAMP_NTZ`, `TIMESTAMP_LTZ`, `TIMESTAMP_TZ`).

**Scenario — Translating a billing ledger DDL from Snowflake to BigQuery without losing decimal precision:**

```sql
-- Snowflake DDL
CREATE TABLE finance.ledger_entries (
    entry_id    NUMBER(38,0),
    amount_usd  NUMBER(18,4),
    posted_at   TIMESTAMP_TZ,
    metadata    VARIANT
);

-- Equivalent BigQuery DDL
CREATE TABLE `finance.ledger_entries` (
    entry_id    INT64,
    amount_usd  NUMERIC(18,4),
    posted_at   TIMESTAMP,
    metadata    JSON
);
```

---

## 10. Semi-Structured Data Handling

Beyond basic JSON extraction, each platform has unique capabilities for querying nested, repeated, and deeply structured data. Data engineers working with event data, logs, and API payloads use these features daily.

### Declaring / Storing Semi-Structured Data

| Feature | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Native type | `JSON`, `STRUCT`, `LIST` | `VARIANT`, `OBJECT`, `ARRAY` | `STRUCT<>`, `ARRAY<>`, `JSON` | `STRUCT<>`, `ARRAY<>`, `MAP<>` |
| Parse from string | `json_extract(col, '$.key')` | `PARSE_JSON(col)` | Auto (JSON columns) | `FROM_JSON(col, schema)` |
| Schema-on-read | ✅ | ✅ | ✅ (JSON type) | ✅ |

### Querying Nested STRUCTs

```sql
-- BigQuery: access STRUCT fields with dot notation
SELECT
    user.name,
    user.address.city
FROM events;

-- Databricks: same dot notation for STRUCT
SELECT
    user.name,
    user.address.city
FROM events;

-- Snowflake: VARIANT uses colon notation
SELECT
    user_data:name::STRING,
    user_data:address.city::STRING
FROM events;
```

### Constructing Semi-Structured Data

```sql
-- BigQuery: STRUCT and ARRAY constructors
SELECT
    STRUCT('John' AS name, 30 AS age) AS user_info,
    ['tag1', 'tag2', 'tag3'] AS tags;

-- Snowflake: OBJECT_CONSTRUCT and ARRAY_CONSTRUCT
SELECT
    OBJECT_CONSTRUCT('name', 'John', 'age', 30) AS user_info,
    ARRAY_CONSTRUCT('tag1', 'tag2', 'tag3') AS tags;

-- Databricks: STRUCT and ARRAY
SELECT
    STRUCT('John' AS name, 30 AS age) AS user_info,
    ARRAY('tag1', 'tag2', 'tag3') AS tags;
```

> [!WARNING]
> In Snowflake, `VARIANT` fields are **untyped** — you must explicitly cast (e.g., `::STRING`, `::INT`) to avoid comparison issues and unexpected sorting behavior. BigQuery `STRUCT` is strongly typed at schema definition time.

> [!TIP]
> When landing evolving webhook schemas in Databricks, combine `FROM_JSON(payload, schema)` with `SCHEMA_OF_JSON(...)` or Delta Lake schema evolution so new JSON keys don't break your Bronze-to-Silver pipeline.

**Scenario — Structuring flattened user telemetry into typed nested structs for downstream analytics:**

```sql
-- Databricks (Spark SQL): parse raw JSON string into a strongly typed STRUCT
SELECT
    event_id,
    FROM_JSON(
        raw_payload,
        'STRUCT<user_id: STRING, amount: DOUBLE, device: STRUCT<os: STRING, version: STRING>>'
    ) AS parsed_event
FROM bronze.raw_telemetry;
```

---

## 11. Approximate Aggregations

When working with very large datasets (billions of rows), exact `COUNT(DISTINCT ...)` is expensive. All major platforms offer approximate alternatives using probabilistic data structures (typically HyperLogLog). These trade a small margin of error for dramatic performance gains.

| Function | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Approx distinct count | `APPROX_COUNT_DISTINCT(col)` | `APPROX_COUNT_DISTINCT(col)` | `APPROX_COUNT_DISTINCT(col)` | `APPROX_COUNT_DISTINCT(col)` |
| HyperLogLog sketch | `❌` | `HLL(col)` + `HLL_ESTIMATE(...)` | `HLL_COUNT.INIT(col)` + `HLL_COUNT.MERGE(...)` | `❌` |
| Approx percentile | `APPROX_QUANTILE(col, 0.5)` | `APPROX_PERCENTILE(col, 0.5)` | `APPROX_QUANTILES(col, 100)[OFFSET(50)]` | `PERCENTILE_APPROX(col, 0.5)` |
| Approx top-k | `❌` | `APPROX_TOP_K(col, k)` | `APPROX_TOP_COUNT(col, k)` | `❌` |

### APPROX_COUNT_DISTINCT

```sql
-- Works on all platforms (function name is the same!)
SELECT
    DATE_TRUNC('DAY', event_ts) AS event_date,  -- adjust for BigQuery arg order
    APPROX_COUNT_DISTINCT(user_id) AS approx_unique_users
FROM clickstream_events
GROUP BY 1;
```

### HyperLogLog Sketches (Mergeable)

```sql
-- Snowflake: build and merge HLL sketches
-- Step 1: Pre-aggregate into HLL sketches per day
CREATE TABLE daily_hll AS
SELECT
    event_date,
    HLL(user_id) AS user_hll
FROM events
GROUP BY event_date;

-- Step 2: Merge sketches for a date range
SELECT HLL_ESTIMATE(HLL_COMBINE(user_hll)) AS weekly_unique_users
FROM daily_hll
WHERE event_date BETWEEN '2026-01-01' AND '2026-01-07';

-- BigQuery: HLL_COUNT functions
SELECT
    HLL_COUNT.MERGE(user_hll) AS weekly_unique_users
FROM (
    SELECT event_date, HLL_COUNT.INIT(user_id) AS user_hll
    FROM events
    GROUP BY event_date
)
WHERE event_date BETWEEN '2026-01-01' AND '2026-01-07';
```

> [!TIP]
> HyperLogLog sketches are **mergeable** — you can pre-aggregate sketches daily and then combine them for arbitrary date ranges without re-scanning raw data. This is invaluable for dashboards with date-range filters over petabyte-scale datasets.

> [!WARNING]
> `APPROX_COUNT_DISTINCT` typically has a ~2% error rate. Never use it where exact counts are required (financial reporting, compliance). Use it for analytics dashboards, monitoring, and exploratory analysis.

**Scenario — Building a pre-aggregated unique-users table for fast dashboard queries:**

```sql
-- BigQuery: daily pre-aggregation with HLL
CREATE TABLE `analytics.daily_user_hll` AS
SELECT
    DATE_TRUNC(event_ts, DAY) AS event_date,
    traffic_source,
    HLL_COUNT.INIT(user_id) AS hll_sketch
FROM `raw.clickstream`
GROUP BY 1, 2;

-- Query: unique users by source, last 30 days (no full scan!)
SELECT
    traffic_source,
    HLL_COUNT.MERGE(hll_sketch) AS unique_users_30d
FROM `analytics.daily_user_hll`
WHERE event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY traffic_source;
```

---

## 12. Materialized Views & Clustering

Materialized views and clustering/partitioning are the primary mechanisms for optimizing query performance in cloud data warehouses. They affect how data is physically stored and pre-computed.

### Materialized Views

| Feature | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Materialized Views | ❌ (DuckDB has no built-in MV) | ✅ `CREATE MATERIALIZED VIEW` | ✅ `CREATE MATERIALIZED VIEW` | ✅ (via Delta Live Tables or `CREATE MATERIALIZED VIEW` in Unity Catalog) |
| Auto-refresh | N/A | ✅ (background, automatic) | ✅ (automatic, max every 30 min) | Via DLT pipelines |
| Incremental refresh | N/A | ✅ | ✅ | ✅ (DLT) |
| Query rewrite | N/A | ✅ (automatic) | ✅ (automatic) | ❌ (manual) |

```sql
-- Snowflake: Materialized View
CREATE MATERIALIZED VIEW mv_daily_revenue AS
SELECT
    DATE_TRUNC('DAY', order_ts) AS order_date,
    region,
    SUM(amount) AS daily_revenue,
    COUNT(*) AS order_count
FROM orders
GROUP BY 1, 2;

-- BigQuery: Materialized View
CREATE MATERIALIZED VIEW `project.dataset.mv_daily_revenue` AS
SELECT
    DATE_TRUNC(order_ts, DAY) AS order_date,
    region,
    SUM(amount) AS daily_revenue,
    COUNT(*) AS order_count
FROM `project.dataset.orders`
GROUP BY 1, 2;
```

> [!WARNING]
> Snowflake materialized views have significant restrictions: no joins, no UDFs, no nested subqueries. BigQuery MVs have similar limitations — no `QUALIFY`, no analytic functions, no `HAVING`. Check the docs before assuming your complex query can be materialized.

### Clustering & Partitioning

| Feature | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Partitioning | ❌ | Automatic micro-partitions | `PARTITION BY` (date, integer range, ingestion time) | `PARTITIONED BY` (Hive-style) |
| Clustering | ❌ | `CLUSTER BY (col1, col2)` | `CLUSTER BY col1, col2` (up to 4) | `ZORDER BY (col1, col2)` |
| Auto-clustering | N/A | ✅ (automatic, background) | ✅ (automatic) | Manual `OPTIMIZE ... ZORDER BY` |

```sql
-- Snowflake: Clustering
ALTER TABLE events CLUSTER BY (event_date, region);

-- BigQuery: Partition + Cluster at creation
CREATE TABLE `project.dataset.events` (
    event_id STRING,
    event_ts TIMESTAMP,
    region STRING,
    payload JSON
)
PARTITION BY DATE(event_ts)
CLUSTER BY region;

-- Databricks: Partition + ZOrder
CREATE TABLE events (
    event_id STRING,
    event_ts TIMESTAMP,
    region STRING,
    payload STRING
)
USING DELTA
PARTITIONED BY (event_date DATE);

-- Optimize with ZOrder (run periodically)
OPTIMIZE events ZORDER BY (region);
```

> [!TIP]
> **Partitioning** splits data into coarse physical segments (usually by date). **Clustering** sorts data within each partition for faster range scans on specific columns. Always partition by your most common filter (usually date), then cluster by the next 1-3 most-filtered columns.

> [!WARNING]
> In BigQuery, over-partitioning (too many small partitions) increases metadata overhead and slows queries. Aim for partitions of at least 1 GB each. In Databricks, too many Hive-style partitions (e.g., `PARTITIONED BY (user_id)` with millions of users) creates a "small files problem."

**Scenario — Optimizing a large event table for dashboard queries filtered by date and region:**

```sql
-- BigQuery: Create optimally partitioned & clustered table
CREATE TABLE `analytics.events_optimized`
PARTITION BY DATE(event_ts)
CLUSTER BY region, event_type
AS SELECT * FROM `raw.events`;

-- Snowflake: Enable automatic clustering
CREATE TABLE analytics.events_optimized
CLUSTER BY (event_date, region)
AS SELECT * FROM raw.events;

-- Verify clustering depth
SELECT SYSTEM$CLUSTERING_INFORMATION('analytics.events_optimized');
```

---

## Quick Reference: Function Name Cheat Sheet

| Operation | ANSI / DuckDB | Snowflake | BigQuery | Databricks |
|---|---|---|---|---|
| Qualify | `QUALIFY` | `QUALIFY` | `QUALIFY` | ❌ (subquery) |
| JSON extract text | `->>` | `col:key::STRING` | `JSON_EXTRACT_SCALAR()` | `GET_JSON_OBJECT()` |
| Flatten array | `UNNEST()` | `LATERAL FLATTEN()` | `UNNEST()` | `EXPLODE()` |
| Merge/Upsert | `MERGE INTO` | `MERGE INTO` | `MERGE INTO` | `MERGE INTO` (Delta) |
| Safe divide | `NULLIF()` | `DIV0()` / `DIV0NULL()` | `SAFE_DIVIDE()` | `TRY_DIVIDE()` |
| String agg | `STRING_AGG()` | `LISTAGG()` | `STRING_AGG()` | `COLLECT_LIST()` + `CONCAT_WS()` |
| Date trunc | `DATE_TRUNC('part', dt)` | `DATE_TRUNC('PART', dt)` | `DATE_TRUNC(dt, PART)` | `DATE_TRUNC('PART', dt)` |
| Add days | `+ INTERVAL '7' DAY` | `DATEADD('DAY', 7, dt)` | `DATE_ADD(dt, INTERVAL 7 DAY)` | `DATE_ADD(dt, 7)` |
| Date diff | `dt1 - dt2` | `DATEDIFF('DAY', dt2, dt1)` | `DATE_DIFF(dt1, dt2, DAY)` | `DATEDIFF(dt1, dt2)` |
| Format date | `STRFTIME()` | `TO_CHAR()` | `FORMAT_DATE()` | `DATE_FORMAT()` |
| Approx distinct | `APPROX_COUNT_DISTINCT()` | `APPROX_COUNT_DISTINCT()` | `APPROX_COUNT_DISTINCT()` | `APPROX_COUNT_DISTINCT()` |
| Clustering | ❌ | `CLUSTER BY` | `CLUSTER BY` | `ZORDER BY` |

---

*Next: [Module 5 — Query Performance, Optimization & Anti-Patterns →](05-performance-tuning.md)*
