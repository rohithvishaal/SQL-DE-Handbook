# Module 1: Quick Syntax & Foundation Cheat Sheet

> A Data Engineering focused reference covering core SQL syntax, joins, set operations, NULL handling, and type casting using dialect-agnostic ANSI SQL.

---

## Table of Contents

1. [Core Operations](#1-core-operations)
2. [Joins & Join Traps](#2-joins--join-traps)
3. [Set Operations](#3-set-operations)
4. [NULL Semantics](#4-null-semantics)
5. [Type Casting & Coercion](#5-type-casting--coercion)

---

## 1. Core Operations

### SELECT

The `SELECT` statement retrieves columns from one or more tables. It is the foundation of every SQL query and supports expressions, aliases, and the `DISTINCT` keyword to eliminate duplicate rows.

```sql
SELECT [DISTINCT] column1 [AS alias1], column2, expression
FROM table_name;
```

**Data Engineering Example**

*Source table:* `raw_events`

| event_id | user_id | event_type | created_at          |
|----------|---------|------------|---------------------|
| 1        | 101     | page_view  | 2024-01-15 08:00:00 |
| 2        | 102     | click      | 2024-01-15 08:05:00 |
| 3        | 101     | page_view  | 2024-01-15 08:10:00 |
| 4        | 103     | signup     | 2024-01-15 09:00:00 |

```sql
SELECT DISTINCT event_type AS activity
FROM raw_events;
```

*Expected output:*

| activity  |
|-----------|
| page_view |
| click     |
| signup    |

> [!WARNING]
> **Gotcha:** `SELECT DISTINCT` applies to the **entire row**, not just the first column. `SELECT DISTINCT a, b` deduplicates on the combination of `(a, b)`, not `a` alone. In data pipelines this can silently produce more rows than expected if you add a column without realizing it breaks your dedup logic.

---

### WHERE

The `WHERE` clause filters rows **before** any aggregation. It supports comparison operators (`=`, `<>`, `<`, `>`, `<=`, `>=`), logical operators (`AND`, `OR`, `NOT`), pattern matching (`LIKE`, `ILIKE`), range checks (`BETWEEN`), and membership tests (`IN`).

```sql
SELECT columns
FROM table_name
WHERE condition1 AND (condition2 OR condition3);
```

**Data Engineering Example**

*Source table:* `pipeline_runs`

| run_id | pipeline_name | status  | duration_sec | run_date   |
|--------|---------------|---------|--------------|------------|
| 1      | etl_orders    | success | 120          | 2024-01-10 |
| 2      | etl_orders    | failed  | 45           | 2024-01-11 |
| 3      | etl_users     | success | 300          | 2024-01-11 |
| 4      | etl_orders    | success | 600          | 2024-01-12 |

```sql
SELECT run_id, pipeline_name, duration_sec
FROM pipeline_runs
WHERE status = 'failed'
   OR (status = 'success' AND duration_sec > 200);
```

*Expected output:*

| run_id | pipeline_name | duration_sec |
|--------|---------------|--------------|
| 2      | etl_orders    | 45           |
| 3      | etl_users     | 300          |
| 4      | etl_orders    | 600          |

> [!WARNING]
> **Gotcha:** Operator precedence — `AND` binds tighter than `OR`. The expression `A OR B AND C` evaluates as `A OR (B AND C)`, not `(A OR B) AND C`. Always use explicit parentheses to avoid subtle filter bugs in complex pipeline logic.

---

### GROUP BY

`GROUP BY` collapses rows that share the same values in the specified columns into summary rows. Every column in the `SELECT` list must either appear in the `GROUP BY` clause or be wrapped in an aggregate function (`COUNT`, `SUM`, `AVG`, `MIN`, `MAX`).

```sql
SELECT group_col, AGG_FUNC(measure_col) AS alias
FROM table_name
WHERE filter_condition
GROUP BY group_col;
```

**Data Engineering Example**

*Source table:* `raw_events` (same as above)

```sql
SELECT
    user_id,
    COUNT(*)           AS total_events,
    MIN(created_at)    AS first_seen,
    MAX(created_at)    AS last_seen
FROM raw_events
GROUP BY user_id;
```

*Expected output:*

| user_id | total_events | first_seen          | last_seen           |
|---------|--------------|---------------------|---------------------|
| 101     | 2            | 2024-01-15 08:00:00 | 2024-01-15 08:10:00 |
| 102     | 1            | 2024-01-15 08:05:00 | 2024-01-15 08:05:00 |
| 103     | 1            | 2024-01-15 09:00:00 | 2024-01-15 09:00:00 |

> [!WARNING]
> **Gotcha:** In MySQL, non-aggregated columns not in `GROUP BY` silently return **arbitrary** values (unless `ONLY_FULL_GROUP_BY` mode is on). ANSI SQL and most modern engines reject such queries. Always explicitly list every non-aggregated column in `GROUP BY`.

---

### HAVING

`HAVING` filters **after** aggregation, whereas `WHERE` filters before. It is the only way to impose conditions on aggregate values.

```sql
SELECT group_col, AGG_FUNC(measure_col) AS alias
FROM table_name
GROUP BY group_col
HAVING AGG_FUNC(measure_col) > threshold;
```

**Data Engineering Example**

*Source table:* `daily_loads`

| load_date  | source_system | row_count |
|------------|---------------|-----------|
| 2024-01-10 | crm           | 15000     |
| 2024-01-10 | erp           | 8000      |
| 2024-01-11 | crm           | 16000     |
| 2024-01-11 | erp           | 200       |
| 2024-01-12 | crm           | 14500     |
| 2024-01-12 | erp           | 9800      |

```sql
SELECT
    source_system,
    AVG(row_count) AS avg_rows
FROM daily_loads
GROUP BY source_system
HAVING AVG(row_count) < 10000;
```

*Expected output:*

| source_system | avg_rows |
|---------------|----------|
| erp           | 6000     |

> [!WARNING]
> **Gotcha:** You **cannot** reference a column alias defined in `SELECT` inside a `HAVING` clause in ANSI SQL. You must repeat the aggregate expression: `HAVING AVG(row_count) < 10000`, not `HAVING avg_rows < 10000`. Some engines (MySQL, BigQuery) allow it, but it is non-portable.

<ClozeDrill
  card-id="m1-having-aggregate-repeat"
  module-id="m1"
  prompt="Recall how to filter aggregated groups in ANSI SQL without relying on non-portable SELECT aliases:"
  :prefix="'SELECT source_system, AVG(row_count) AS avg_rows\nFROM daily_loads\nGROUP BY source_system\n'"
  answer="HAVING AVG(row_count) < 10000"
  suffix=";"
/>

---

### ORDER BY

`ORDER BY` sorts the final result set. It is the **only** clause that guarantees row order — without it, the database may return rows in any order across executions.

```sql
SELECT columns
FROM table_name
ORDER BY column1 [ASC | DESC] [NULLS FIRST | NULLS LAST],
         column2 [ASC | DESC];
```

**Data Engineering Example**

```sql
SELECT pipeline_name, run_date, duration_sec
FROM pipeline_runs
ORDER BY pipeline_name ASC, duration_sec DESC;
```

*Expected output:*

| pipeline_name | run_date   | duration_sec |
|---------------|------------|--------------|
| etl_orders    | 2024-01-12 | 600          |
| etl_orders    | 2024-01-10 | 120          |
| etl_orders    | 2024-01-11 | 45           |
| etl_users     | 2024-01-11 | 300          |

> [!WARNING]
> **Gotcha:** Without an `ORDER BY`, repeated runs of the same query can return rows in different orders — this causes non-deterministic diffs in data validation tests and snapshot-based pipelines. Always add an explicit `ORDER BY` when the downstream consumer depends on row order.

---

### LIMIT / OFFSET

`LIMIT` restricts the number of rows returned; `OFFSET` skips a specified number of rows before starting to return results. Together they enable pagination, but they have important performance and correctness implications.

```sql
-- ANSI / PostgreSQL / MySQL / SQLite
SELECT columns
FROM table_name
ORDER BY sort_col
LIMIT n OFFSET m;

-- SQL Server / Azure Synapse
SELECT columns
FROM table_name
ORDER BY sort_col
OFFSET m ROWS FETCH NEXT n ROWS ONLY;
```

**Data Engineering Example**

*Source table:* `pipeline_runs` (from above)

```sql
-- Get page 2 (rows 3-4) of the longest pipeline runs
SELECT run_id, pipeline_name, duration_sec
FROM pipeline_runs
ORDER BY duration_sec DESC
LIMIT 2 OFFSET 2;
```

*Expected output:*

| run_id | pipeline_name | duration_sec |
|--------|---------------|--------------|
| 1      | etl_orders    | 120          |
| 2      | etl_orders    | 45           |

> [!WARNING]
> **Gotcha:** `LIMIT` without `ORDER BY` is non-deterministic — the engine picks any rows it likes. In data pipelines, using `LIMIT` for sampling without a deterministic sort produces unreproducible results. Also, large `OFFSET` values are expensive because the engine must scan and discard rows — prefer keyset (cursor-based) pagination for production pipelines.

---

## 2. Joins & Join Traps

### INNER JOIN

An `INNER JOIN` returns only rows where the join condition is satisfied in **both** tables. Rows in either table that have no match are excluded from the result.

```sql
SELECT a.col, b.col
FROM table_a AS a
INNER JOIN table_b AS b
    ON a.key = b.key;
```

**Data Engineering Example**

*`orders`*

| order_id | customer_id | amount |
|----------|-------------|--------|
| 1        | 101         | 250.00 |
| 2        | 102         | 75.00  |
| 3        | 999         | 30.00  |

*`customers`*

| customer_id | name    |
|-------------|---------|
| 101         | Alice   |
| 102         | Bob     |
| 103         | Charlie |

```sql
SELECT o.order_id, c.name, o.amount
FROM orders AS o
INNER JOIN customers AS c
    ON o.customer_id = c.customer_id;
```

*Expected output:*

| order_id | name  | amount |
|----------|-------|--------|
| 1        | Alice | 250.00 |
| 2        | Bob   | 75.00  |

> [!WARNING]
> **Gotcha:** If the join key contains NULLs, those rows will **never** match — `NULL = NULL` evaluates to `UNKNOWN`, not `TRUE`. This silently drops rows in data pipelines. Use `IS NOT DISTINCT FROM` (or `COALESCE`) when you need NULL-safe joins.

---

### LEFT JOIN (LEFT OUTER JOIN)

A `LEFT JOIN` returns **all** rows from the left table and the matching rows from the right table. Where there is no match, the right-side columns are filled with NULLs.

```sql
SELECT a.col, b.col
FROM table_a AS a
LEFT JOIN table_b AS b
    ON a.key = b.key;
```

**Data Engineering Example**

```sql
SELECT o.order_id, c.name, o.amount
FROM orders AS o
LEFT JOIN customers AS c
    ON o.customer_id = c.customer_id;
```

*Expected output:*

| order_id | name  | amount |
|----------|-------|--------|
| 1        | Alice | 250.00 |
| 2        | Bob   | 75.00  |
| 3        | NULL  | 30.00  |

> [!WARNING]
> **Gotcha:** Placing a filter on the right table's column in the `WHERE` clause converts a `LEFT JOIN` into an `INNER JOIN`. For example, `WHERE c.country = 'US'` excludes NULLs and drops all unmatched rows. Move such filters into the `ON` clause to preserve the LEFT JOIN semantics.

---

### RIGHT JOIN (RIGHT OUTER JOIN)

A `RIGHT JOIN` returns all rows from the **right** table and matching rows from the left. It is the mirror image of `LEFT JOIN`. Most teams prefer rewriting `RIGHT JOIN` as a `LEFT JOIN` with the tables swapped for readability.

```sql
SELECT a.col, b.col
FROM table_a AS a
RIGHT JOIN table_b AS b
    ON a.key = b.key;
```

**Data Engineering Example**

```sql
SELECT o.order_id, c.name
FROM orders AS o
RIGHT JOIN customers AS c
    ON o.customer_id = c.customer_id;
```

*Expected output:*

| order_id | name    |
|----------|---------|
| 1        | Alice   |
| 2        | Bob     |
| NULL     | Charlie |

> [!WARNING]
> **Gotcha:** `RIGHT JOIN` is rarely used in practice and can confuse code reviewers. Convention in most data teams is to use `LEFT JOIN` exclusively by swapping table positions. This consistency makes pipeline SQL easier to audit.

---

### FULL OUTER JOIN

A `FULL OUTER JOIN` returns all rows from both tables. Where there is no match, the missing side is filled with NULLs. It is essential for data reconciliation — comparing two data sources to find rows that exist in one but not the other.

```sql
SELECT a.col, b.col
FROM table_a AS a
FULL OUTER JOIN table_b AS b
    ON a.key = b.key;
```

**Data Engineering Example**

*`source_a` (CRM extract)*

| customer_id | email            |
|-------------|------------------|
| 101         | alice@example.com|
| 102         | bob@example.com  |

*`source_b` (billing extract)*

| customer_id | email            |
|-------------|------------------|
| 102         | bob@example.com  |
| 103         | charlie@co.com   |

```sql
SELECT
    COALESCE(a.customer_id, b.customer_id) AS customer_id,
    a.email AS crm_email,
    b.email AS billing_email,
    CASE
        WHEN a.customer_id IS NULL THEN 'Missing in CRM'
        WHEN b.customer_id IS NULL THEN 'Missing in Billing'
        ELSE 'Matched'
    END AS reconciliation_status
FROM source_a AS a
FULL OUTER JOIN source_b AS b
    ON a.customer_id = b.customer_id;
```

*Expected output:*

| customer_id | crm_email         | billing_email    | reconciliation_status |
|-------------|-------------------|------------------|-----------------------|
| 101         | alice@example.com | NULL             | Missing in Billing    |
| 102         | bob@example.com   | bob@example.com  | Matched               |
| 103         | NULL              | charlie@co.com   | Missing in CRM        |

> [!WARNING]
> **Gotcha:** MySQL does **not** support `FULL OUTER JOIN`. You must emulate it with a `LEFT JOIN` + `UNION ALL` + a filtered `RIGHT JOIN` (or anti-join). Always verify engine support.

---

### CROSS JOIN

A `CROSS JOIN` produces the Cartesian product of two tables — every row from the left table paired with every row from the right table. It is rarely used accidentally but is powerful for generating date spines, parameter grids, or scaffolding dimension tables.

```sql
SELECT a.col, b.col
FROM table_a AS a
CROSS JOIN table_b AS b;
```

**Data Engineering Example**

*`date_spine`*

| report_date |
|-------------|
| 2024-01-01  |
| 2024-01-02  |
| 2024-01-03  |

*`metrics`*

| metric_name |
|-------------|
| revenue     |
| users       |

```sql
SELECT d.report_date, m.metric_name
FROM date_spine AS d
CROSS JOIN metrics AS m;
```

*Expected output (6 rows):*

| report_date | metric_name |
|-------------|-------------|
| 2024-01-01  | revenue     |
| 2024-01-01  | users       |
| 2024-01-02  | revenue     |
| 2024-01-02  | users       |
| 2024-01-03  | revenue     |
| 2024-01-03  | users       |

> [!WARNING]
> **Gotcha:** A `CROSS JOIN` on two large tables produces `rows_A × rows_B` output rows and can crash your cluster or exhaust memory. In data pipelines, an accidental cross join is usually caused by omitting the `ON` clause — some engines (e.g., Spark SQL) silently treat `JOIN` without `ON` as a `CROSS JOIN`.

---

### ANTI JOIN

An `ANTI JOIN` returns rows from the left table that have **no match** in the right table. ANSI SQL has no `ANTI JOIN` keyword; it is expressed using `LEFT JOIN ... WHERE right.key IS NULL` or `NOT EXISTS`.

```sql
-- Pattern 1: LEFT JOIN + IS NULL
SELECT a.*
FROM table_a AS a
LEFT JOIN table_b AS b
    ON a.key = b.key
WHERE b.key IS NULL;

-- Pattern 2: NOT EXISTS (often preferred by optimizers)
SELECT a.*
FROM table_a AS a
WHERE NOT EXISTS (
    SELECT 1 FROM table_b AS b WHERE b.key = a.key
);
```

**Data Engineering Example**

```sql
-- Find orders with no matching customer (orphan records)
SELECT o.*
FROM orders AS o
LEFT JOIN customers AS c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;
```

*Expected output:*

| order_id | customer_id | amount |
|----------|-------------|--------|
| 3        | 999         | 30.00  |

> [!WARNING]
> **Gotcha:** When using the `LEFT JOIN + IS NULL` pattern, make sure the `IS NULL` check is on a non-nullable column of the right table (typically the join key or the primary key). Checking a column that is legitimately nullable will produce false positives.

---

### SEMI JOIN

A `SEMI JOIN` returns rows from the left table where **at least one match** exists in the right table, but **does not duplicate rows** when multiple matches exist (unlike `INNER JOIN`). Like `ANTI JOIN`, there is no `SEMI JOIN` keyword in ANSI SQL.

```sql
-- Pattern: EXISTS
SELECT a.*
FROM table_a AS a
WHERE EXISTS (
    SELECT 1 FROM table_b AS b WHERE b.key = a.key
);

-- Pattern: IN (simpler but beware NULLs)
SELECT a.*
FROM table_a AS a
WHERE a.key IN (SELECT b.key FROM table_b);
```

**Data Engineering Example**

*`users`*

| user_id | name    |
|---------|---------|
| 101     | Alice   |
| 102     | Bob     |
| 103     | Charlie |

*`login_events`* (many logins per user)

| event_id | user_id | login_at            |
|----------|---------|---------------------|
| 1        | 101     | 2024-01-15 08:00:00 |
| 2        | 101     | 2024-01-15 09:00:00 |
| 3        | 102     | 2024-01-15 10:00:00 |

```sql
-- Users who logged in at least once (no duplicates)
SELECT u.*
FROM users AS u
WHERE EXISTS (
    SELECT 1 FROM login_events AS le WHERE le.user_id = u.user_id
);
```

*Expected output:*

| user_id | name  |
|---------|-------|
| 101     | Alice |
| 102     | Bob   |

> [!WARNING]
> **Gotcha:** The `IN` subquery pattern breaks when the subquery returns NULLs. `x IN (1, 2, NULL)` where `x = 3` evaluates to `UNKNOWN` (not `FALSE`), and wrapping it with `NOT IN` returns zero rows. Prefer `EXISTS` / `NOT EXISTS` for NULL safety.

---

### Fan-Out & Cartesian Explosion Diagnosis

A **fan-out** (Cartesian explosion) occurs when a join produces more rows than expected because the join key is not unique on one or both sides. This is the #1 cause of incorrect aggregate values in data pipelines.

**Diagnosis Pattern**

```sql
-- Step 1: Check if the join key is unique
SELECT join_key, COUNT(*) AS cnt
FROM table_b
GROUP BY join_key
HAVING COUNT(*) > 1;

-- Step 2: Compare row counts before and after join
SELECT
    (SELECT COUNT(*) FROM table_a) AS rows_before,
    (SELECT COUNT(*) FROM table_a JOIN table_b USING (key)) AS rows_after;
-- If rows_after > rows_before, you have a fan-out.
```

**Data Engineering Example**

*`orders`*

| order_id | product_id |
|----------|------------|
| 1        | P1         |
| 2        | P2         |

*`promotions`* (multiple promos per product)

| promo_id | product_id | discount |
|----------|------------|----------|
| A        | P1         | 10       |
| B        | P1         | 20       |
| C        | P2         | 5        |

```sql
-- Dangerous: fan-out doubles order 1
SELECT o.order_id, p.discount
FROM orders AS o
INNER JOIN promotions AS p
    ON o.product_id = p.product_id;
```

*Result (3 rows from 2 orders — fan-out!):*

| order_id | discount |
|----------|----------|
| 1        | 10       |
| 1        | 20       |
| 2        | 5        |

> [!WARNING]
> **Gotcha:** Fan-outs silently inflate `SUM`, `COUNT`, and other aggregates. Before joining, always verify the grain (uniqueness) of each table's join key. Use `COUNT(*) ... GROUP BY key HAVING COUNT(*) > 1` to check. In dbt, use the `unique` test on your models' primary keys.

---

## 3. Set Operations

### UNION vs UNION ALL

`UNION ALL` concatenates two result sets preserving all rows (including duplicates). `UNION` (without `ALL`) performs `UNION ALL` followed by an implicit `DISTINCT`, which adds a sort or hash step.

```sql
SELECT columns FROM table_a
UNION ALL              -- keeps duplicates, faster
SELECT columns FROM table_b;

SELECT columns FROM table_a
UNION                  -- removes duplicates, slower
SELECT columns FROM table_b;
```

**Data Engineering Example**

*`events_2024_q1`*

| user_id | event_type |
|---------|------------|
| 101     | click      |
| 102     | view       |

*`events_2024_q2`*

| user_id | event_type |
|---------|------------|
| 101     | click      |
| 103     | signup     |

```sql
-- Combine quarterly partitions (preserving duplicates with UNION ALL)
SELECT user_id, event_type FROM events_2024_q1
UNION ALL
SELECT user_id, event_type FROM events_2024_q2;
```

*Expected output (`UNION ALL` — 4 rows):*

| user_id | event_type |
|---------|------------|
| 101     | click      |
| 102     | view       |
| 101     | click      |
| 103     | signup     |

```sql
-- Combine and deduplicate with UNION (removes the duplicate 101 / click row)
SELECT user_id, event_type FROM events_2024_q1
UNION
SELECT user_id, event_type FROM events_2024_q2;
```

*Expected output (`UNION` — 3 rows):*

| user_id | event_type |
|---------|------------|
| 101     | click      |
| 102     | view       |
| 103     | signup     |

> [!WARNING]
> **Gotcha:** In data pipelines, `UNION` (without `ALL`) silently removes legitimate duplicate events. The dedup sort is also expensive on large tables. Default to `UNION ALL` unless you specifically need deduplication — and if you do, make it explicit with a `DISTINCT` on specific columns so intent is clear.

---

### INTERSECT

`INTERSECT` returns only the rows that appear in **both** result sets. Like `UNION`, it implicitly deduplicates.

```sql
SELECT columns FROM table_a
INTERSECT
SELECT columns FROM table_b;
```

**Data Engineering Example**

```sql
-- Users active in both quarters
SELECT user_id FROM events_2024_q1
INTERSECT
SELECT user_id FROM events_2024_q2;
```

*Expected output:*

| user_id |
|---------|
| 101     |

> [!WARNING]
> **Gotcha:** `INTERSECT` treats NULLs as equal for comparison purposes (unlike `=`). Two rows `(1, NULL)` and `(1, NULL)` **will** match. This is convenient but inconsistent with how NULLs behave in `JOIN` or `WHERE` conditions — be aware of this semantic difference.

---

### EXCEPT / MINUS

`EXCEPT` (called `MINUS` in Oracle) returns rows from the first query that are **not** present in the second query. It is the set-operation counterpart of the `ANTI JOIN`.

```sql
SELECT columns FROM table_a
EXCEPT                 -- Oracle: MINUS
SELECT columns FROM table_b;
```

**Data Engineering Example**

```sql
-- Users who were active in Q1 but churned (not in Q2)
SELECT user_id FROM events_2024_q1
EXCEPT
SELECT user_id FROM events_2024_q2;
```

*Expected output:*

| user_id |
|---------|
| 102     |

> [!WARNING]
> **Gotcha:** The column count and data types must match across all set operations. A mismatch in column order (e.g., swapping `user_id` and `event_date` between the two `SELECT`s) will either error or silently compare wrong columns, producing garbage results.

---

## 4. NULL Semantics

### Three-Valued Logic

SQL uses **three-valued logic**: every comparison evaluates to `TRUE`, `FALSE`, or `UNKNOWN`. Any operation involving `NULL` yields `UNKNOWN`. `WHERE` and `HAVING` clauses only include rows where the condition is `TRUE` — rows with `UNKNOWN` are excluded, just like `FALSE`.

```sql
-- All of these evaluate to UNKNOWN (not TRUE, not FALSE):
NULL = NULL        -- UNKNOWN
NULL <> 1          -- UNKNOWN
NULL > 0           -- UNKNOWN
NULL AND TRUE      -- UNKNOWN
NOT NULL           -- UNKNOWN
```

**Data Engineering Example**

*`sensor_readings`*

| sensor_id | temperature |
|-----------|-------------|
| S1        | 22.5        |
| S2        | NULL        |
| S3        | 18.0        |

```sql
-- This will NOT return S2 — NULL <> 20 is UNKNOWN
SELECT * FROM sensor_readings WHERE temperature <> 20;
```

*Expected output (S2 is excluded):*

| sensor_id | temperature |
|-----------|-------------|
| S1        | 22.5        |
| S3        | 18.0        |

```sql
-- To include S2, explicitly handle NULL:
SELECT * FROM sensor_readings
WHERE temperature <> 20 OR temperature IS NULL;
```

> [!WARNING]
> **Gotcha:** `NOT IN` with NULLs is the classic trap. `WHERE x NOT IN (1, 2, NULL)` returns **zero rows** for every value of `x`, because `x <> NULL` is `UNKNOWN`, making the entire expression `UNKNOWN`. Use `NOT EXISTS` instead.

---

### COALESCE

`COALESCE` returns the first non-NULL value from a list of expressions. It is ANSI SQL and works on all engines. It is essential for providing defaults, merging columns from different sources, and handling optional fields.

```sql
COALESCE(expr1, expr2, ..., exprN)
```

**Data Engineering Example**

*`user_profiles`*

| user_id | preferred_name | full_name    | email            |
|---------|----------------|--------------|------------------|
| 1       | Al             | Alice Smith  | alice@co.com     |
| 2       | NULL           | Bob Jones    | bob@co.com       |
| 3       | NULL           | NULL         | charlie@co.com   |

```sql
SELECT
    user_id,
    COALESCE(preferred_name, full_name, email) AS display_name
FROM user_profiles;
```

*Expected output:*

| user_id | display_name   |
|---------|----------------|
| 1       | Al             |
| 2       | Bob Jones      |
| 3       | charlie@co.com |

> [!WARNING]
> **Gotcha:** `COALESCE` evaluates arguments left to right and returns the first non-NULL value. If **all** arguments are NULL, the result is NULL — not an empty string. To guarantee a non-NULL result, always include a literal default as the last argument: `COALESCE(col1, col2, 'unknown')`.

---

### NULLIF

`NULLIF(a, b)` returns `NULL` if `a = b`, otherwise returns `a`. It is commonly used to convert sentinel values (like empty strings or zeros) into proper NULLs for correct aggregate calculations.

```sql
NULLIF(expression, value_to_nullify)
```

**Data Engineering Example**

*`legacy_records`*

| record_id | status   |
|-----------|----------|
| 1         | active   |
| 2         |          |
| 3         | inactive |

```sql
-- Convert empty strings (common in CSV imports) to NULL
SELECT
    record_id,
    NULLIF(status, '') AS clean_status
FROM legacy_records;
```

*Expected output:*

| record_id | clean_status |
|-----------|--------------|
| 1         | active       |
| 2         | NULL         |
| 3         | inactive     |

> [!WARNING]
> **Gotcha:** `NULLIF` is asymmetric — `NULLIF(a, b)` returns NULL when `a = b`, but `NULLIF(b, a)` returns NULL when `b = a`. This matters when the arguments are different types; implicit casting may produce unexpected results. Also, do not confuse `NULLIF` with `IFNULL`/`NVL` — they do the **opposite** thing.

---

### NVL / IFNULL

`NVL(expr, default)` (Oracle) and `IFNULL(expr, default)` (MySQL, SQLite) are two-argument shortcuts equivalent to `COALESCE(expr, default)`. They return `default` if `expr` is NULL.

```sql
-- Oracle
NVL(column, default_value)

-- MySQL / SQLite
IFNULL(column, default_value)

-- ANSI equivalent (preferred for portability)
COALESCE(column, default_value)
```

**Data Engineering Example**

*`shipments`*

| order_id | shipping_cost |
|----------|---------------|
| 1        | 12.50         |
| 2        | NULL          |
| 3        | 8.00          |

```sql
-- Replace NULL shipping costs with 0 (portable ANSI COALESCE; Oracle NVL(shipping_cost, 0))
SELECT
    order_id,
    COALESCE(shipping_cost, 0) AS shipping_cost
FROM shipments;
```

*Expected output:*

| order_id | shipping_cost |
|----------|---------------|
| 1        | 12.50         |
| 2        | 0.00          |
| 3        | 8.00          |

> [!WARNING]
> **Gotcha:** `NVL` and `IFNULL` are **not ANSI SQL** — they are vendor-specific. If your pipeline runs on Snowflake, BigQuery, or PostgreSQL, use `COALESCE` for portability. Also, `NVL` in Oracle always evaluates **both** arguments (unlike `COALESCE` which short-circuits), so avoid expensive expressions in the second argument.

---

### IS DISTINCT FROM

`IS DISTINCT FROM` is a NULL-safe equality comparison. It treats NULLs as equal to each other and returns a definitive `TRUE` or `FALSE` — never `UNKNOWN`. Its negation is `IS NOT DISTINCT FROM`.

```sql
-- Returns TRUE/FALSE, never UNKNOWN
a IS DISTINCT FROM b
a IS NOT DISTINCT FROM b
```

**Data Engineering Example**

*`snapshot_old`*

| user_id | status   |
|---------|----------|
| 1       | active   |
| 2       | NULL     |

*`snapshot_new`*

| user_id | status   |
|---------|----------|
| 1       | active   |
| 2       | NULL     |

```sql
-- Detect actual changes between snapshots (NULL-safe)
SELECT o.user_id
FROM snapshot_old AS o
JOIN snapshot_new AS n ON o.user_id = n.user_id
WHERE o.status IS DISTINCT FROM n.status;
```

*Expected output:* (empty — both snapshots are the same, even the NULLs)

| user_id |
|---------|
| *(no rows)* |

> [!WARNING]
> **Gotcha:** Not all engines support `IS DISTINCT FROM`. MySQL requires `<=>` (the NULL-safe equality operator) and you negate it with `NOT (a <=> b)`. BigQuery supports it as `IS DISTINCT FROM`. Always check your engine's documentation.

---

## 5. Type Casting & Coercion

### CAST

`CAST` explicitly converts a value from one data type to another. It is ANSI SQL and supported by all major engines. It fails at runtime if the conversion is impossible.

```sql
CAST(expression AS target_type)

-- Shorthand (PostgreSQL)
expression::target_type
```

**Data Engineering Example**

*`raw_ingestion`*

| record_id | amount_str | event_date_str |
|-----------|------------|----------------|
| 1         | 1500.50    | 2024-01-15     |
| 2         | 299.99     | 2024-02-20     |

```sql
SELECT
    record_id,
    CAST(amount_str AS DECIMAL(10, 2))   AS amount,
    CAST(event_date_str AS DATE)         AS event_date
FROM raw_ingestion;
```

*Expected output:*

| record_id | amount  | event_date |
|-----------|---------|------------|
| 1         | 1500.50 | 2024-01-15 |
| 2         | 299.99  | 2024-02-20 |

> [!WARNING]
> **Gotcha:** `CAST` is **strict** — if a value cannot be converted (e.g., `CAST('abc' AS INTEGER)`), the query fails with an error, which can crash your entire pipeline run. For raw/staging data that may contain malformed values, use `TRY_CAST` or `SAFE_CAST` instead.

---

### TRY_CAST / SAFE_CAST

`TRY_CAST` (SQL Server, Snowflake, Databricks) and `SAFE_CAST` (BigQuery) attempt the conversion but return `NULL` instead of raising an error when the cast fails. This is critical for data pipelines processing dirty or unvalidated source data.

```sql
-- SQL Server / Snowflake / Databricks
TRY_CAST(expression AS target_type)

-- BigQuery
SAFE_CAST(expression AS target_type)

-- PostgreSQL (no built-in TRY_CAST — use a custom function or regex guard)
```

**Data Engineering Example**

*`raw_csv_import`*

| row_num | revenue_str |
|---------|-------------|
| 1       | 1200.00     |
| 2       | N/A         |
| 3       | 850.75      |
| 4       | -           |

```sql
SELECT
    row_num,
    revenue_str,
    TRY_CAST(revenue_str AS DECIMAL(10, 2)) AS revenue_clean
FROM raw_csv_import;
```

*Expected output:*

| row_num | revenue_str | revenue_clean |
|---------|-------------|---------------|
| 1       | 1200.00     | 1200.00       |
| 2       | N/A         | NULL          |
| 3       | 850.75      | 850.75        |
| 4       | -           | NULL          |

> [!WARNING]
> **Gotcha:** `TRY_CAST` silently turns bad data into NULLs, which can mask data quality issues. In production pipelines, combine it with a data quality check: `SELECT COUNT(*) FROM raw WHERE TRY_CAST(col AS INT) IS NULL AND col IS NOT NULL` — this tells you how many rows had unparseable values, so you can alert on regressions.

---

### Safe Parsing Patterns

When `TRY_CAST` is not available or when you need more control over parsing (e.g., date formats, regex validation), use safe parsing patterns that combine conditional logic with `CAST`.

```sql
-- Guard with a regex or CASE before casting
SELECT
    CASE
        WHEN value ~ '^\d+$'                  -- PostgreSQL regex
        THEN CAST(value AS INTEGER)
        ELSE NULL
    END AS parsed_int
FROM raw_data;

-- BigQuery: SAFE.PARSE_DATE for date strings
SAFE.PARSE_DATE('%Y-%m-%d', date_string)

-- Snowflake: TRY_TO_DATE / TRY_TO_NUMBER
TRY_TO_DATE(date_string, 'YYYY-MM-DD')
TRY_TO_NUMBER(numeric_string, 10, 2)
```

**Data Engineering Example**

*`api_responses`*

| response_id | timestamp_str        |
|-------------|----------------------|
| 1           | 2024-01-15T08:30:00Z |
| 2           | invalid_ts           |
| 3           | 2024-01-16T12:00:00Z |

```sql
-- Guard with format validation before CAST (ANSI-portable pattern)
SELECT
    response_id,
    CASE
        WHEN timestamp_str LIKE '____-__-__T__:__:__Z'
        THEN CAST(SUBSTRING(timestamp_str, 1, 10) AS DATE)
        ELSE NULL
    END AS parsed_date
FROM api_responses;
```

*Expected output:*

| response_id | parsed_date |
|-------------|-------------|
| 1           | 2024-01-15  |
| 2           | NULL        |
| 3           | 2024-01-16  |

> [!WARNING]
> **Gotcha:** Date/time parsing is the most common source of silent data corruption in pipelines. A format mismatch can swap month and day (`01/02/2024` → Jan 2 or Feb 1?) without any error. Always specify the format explicitly and never rely on implicit parsing. Add data quality assertions that check for NULL parse results in your staging layer.

---

*End of Module 1*
