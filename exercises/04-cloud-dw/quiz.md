# Module 4 Quiz: Cloud Data Warehouse Nuance Matrix

> Test your ability to spot dialect differences and write accurate SQL across **ANSI/DuckDB**, **Snowflake**, **Google BigQuery**, and **Databricks (Spark SQL)**.

---

## Question 1: Window Filtering (`QUALIFY`) Migration

You are migrating a customer-deduplication model from **Snowflake** to **Databricks (Spark SQL)**. The original query is:

```sql
SELECT
    customer_id,
    email,
    updated_at
FROM bronze.raw_customers
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY updated_at DESC
) = 1;
```

**Task:**
1. Will this query run natively on **Databricks**, **BigQuery**, and **DuckDB**?
2. Rewrite the query so it executes cleanly in **Databricks (Spark SQL)**.

---

## Question 2: JSON Extraction Syntax Per Platform

A landing table `raw_events` stores JSON event payloads in a column named `payload` (parsed as `VARIANT` in Snowflake, `JSON` in DuckDB/BigQuery, and `STRING` in Databricks). You need to extract:
- `event_id` (as text/string)
- nested `device.os` (as text/string)
- first item in the array `items[0]` (as text/string)

Match each snippet to the correct platform (**DuckDB**, **Snowflake**, **BigQuery**, or **Databricks**), and identify the **one broken snippet** containing a syntax/behavior error:

**Snippet A:**
```sql
SELECT
    payload ->> 'event_id'          AS event_id,
    payload -> 'device' ->> 'os'    AS device_os,
    payload -> 'items' ->> 0        AS first_item
FROM raw_events;
```

**Snippet B:**
```sql
SELECT
    JSON_EXTRACT_SCALAR(payload, '$.event_id')   AS event_id,
    JSON_EXTRACT(payload, '$.device.os')         AS device_os,
    JSON_EXTRACT_SCALAR(payload, '$.items[0]')   AS first_item
FROM raw_events;
```

**Snippet C:**
```sql
SELECT
    payload:event_id::STRING        AS event_id,
    payload:device.os::STRING       AS device_os,
    payload:items[0]::STRING        AS first_item
FROM raw_events;
```

**Snippet D:**
```sql
SELECT
    GET_JSON_OBJECT(payload, '$.event_id')   AS event_id,
    GET_JSON_OBJECT(payload, '$.device.os')  AS device_os,
    GET_JSON_OBJECT(payload, '$.items[0]')   AS first_item
FROM raw_events;
```

---

## Question 3: Array Flattening Without Dropping Records

An e-commerce `orders` table has an `order_id` column and an array column `discount_codes`. Some orders have **no discount codes** (`NULL` or empty array `[]`).

A junior engineer writes the following **Databricks (Spark SQL)** query, and the finance team complains that total order counts dropped by 65%:

```sql
SELECT
    o.order_id,
    code
FROM orders o
LATERAL VIEW EXPLODE(o.discount_codes) t AS code;
```

**Task:**
1. Why did 65% of the orders vanish from the result?
2. Write the corrected array-flattening query that preserves orders with `NULL` or empty arrays for **all three**:
   - **Databricks (Spark SQL)**
   - **Snowflake**
   - **BigQuery**

---

## Question 4: `MERGE INTO` With Hard-Delete Propagation

Your team runs a nightly `MERGE INTO` pipeline syncing `staging_accounts` into `dim_accounts`. When an account is deleted upstream, it no longer appears in `staging_accounts`, and you must delete it from `dim_accounts` as part of the `MERGE`.

Consider this query:

```sql
MERGE INTO dim_accounts AS tgt
USING staging_accounts AS src
ON tgt.account_id = src.account_id
WHEN MATCHED THEN
    UPDATE SET plan = src.plan, updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (account_id, plan, updated_at)
    VALUES (src.account_id, src.plan, CURRENT_TIMESTAMP())
WHEN NOT MATCHED BY SOURCE THEN
    DELETE;
```

**Task:**
1. Which of the four platforms (**DuckDB**, **Snowflake**, **BigQuery**, **Databricks**) support `WHEN NOT MATCHED BY SOURCE THEN DELETE`?
2. What table format requirement must `dim_accounts` satisfy for `MERGE INTO` to work in **Databricks**?
3. What silent failure occurs in **Snowflake** if `staging_accounts` contains two rows with the same `account_id`?

---

## Question 5: Safe Division & Downstream `AVG()` Trap

You are calculating daily conversion rate (`conversions / clicks`) in a marketing mart where some low-traffic campaigns have `clicks = 0`.

Which query produces the **most accurate** weekly average conversion rate across campaigns in **Snowflake**, **BigQuery**, and **DuckDB**? Explain the difference between Option A and Option B in Snowflake:

- **Option A (Snowflake):** `SELECT DIV0(conversions, clicks) AS conv_rate FROM campaigns;`
- **Option B (Snowflake):** `SELECT DIV0NULL(conversions, clicks) AS conv_rate FROM campaigns;`
- **Option C (BigQuery):** `SELECT SAFE_DIVIDE(conversions, clicks) AS conv_rate FROM campaigns;`
- **Option D (Universal):** `SELECT conversions / NULLIF(clicks, 0) AS conv_rate FROM campaigns;`

---

## Question 6: String Aggregation Across Dialects

You need a comma-separated, alphabetically sorted list of **unique** tags per `ticket_id` from a `support_ticket_tags(ticket_id, tag_name)` table.

Write the valid SQL query for each of the following platforms:
1. **Snowflake**
2. **BigQuery**
3. **Databricks (Spark SQL)**

*(Pay close attention to deduplication and deterministic sorting in each engine!)*

---

## Question 7: Date Truncation & Date Arithmetic Pitfalls

The following query runs cleanly in **Snowflake** to compute 30-day rolling order counts anchored to the start of the month:

```sql
SELECT
    DATE_TRUNC('MONTH', order_ts) AS order_month,
    DATEADD('DAY', 30, order_ts)  AS due_date,
    DATEDIFF('DAY', created_ts, shipped_ts) AS fulfillment_days
FROM orders;
```

Someone copies this query directly into **Google BigQuery** and hits multiple syntax errors.

**Task:**
1. Identify all **three** dialect incompatibilities in BigQuery.
2. Rewrite the query in valid **BigQuery** SQL and **DuckDB** SQL.

---

## Question 8: Mergeable HyperLogLog Sketches & Clustering

A product analytics team runs a dashboard querying **unique active users** over arbitrary custom date ranges (e.g., 7 days, 30 days, 90 days) against a 20 TB `clickstream` table. Exact `COUNT(DISTINCT user_id)` is too slow and expensive.

**Task:**
1. Why can't you store daily `APPROX_COUNT_DISTINCT(user_id)` integers in a summary table and sum them up for a 30-day unique user count?
2. Write the **BigQuery** SQL to:
   - Create a partitioned & clustered daily HLL sketch table (`analytics.daily_user_hll`) partitioned by `event_date` and clustered by `platform`.
   - Query the 30-day unique user count per `platform` by merging those sketches.

---

*Open the **Solution & Explanation** tab on any card above to check the worked dialect solutions.*
