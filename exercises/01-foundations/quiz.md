# Module 1 Quiz: SQL Foundations & Core Operations

Test your understanding of core SQL clauses, join semantics and traps, set operations, three-valued NULL logic, and safe type casting in Data Engineering pipelines.

---

## Part A: Multiple Choice

### Question 1 — Logical Query Execution & Filtering
Which query is **valid** in strict ANSI SQL to return only `source_system` values whose average daily row count exceeds `10000`?

- **A.**
  ```sql
  SELECT source_system, AVG(row_count) AS avg_rows
  FROM daily_loads
  WHERE AVG(row_count) > 10000
  GROUP BY source_system;
  ```
- **B.**
  ```sql
  SELECT source_system, AVG(row_count) AS avg_rows
  FROM daily_loads
  GROUP BY source_system
  HAVING avg_rows > 10000;
  ```
- **C.**
  ```sql
  SELECT source_system, AVG(row_count) AS avg_rows
  FROM daily_loads
  GROUP BY source_system
  HAVING AVG(row_count) > 10000;
  ```
- **D.**
  ```sql
  SELECT source_system, AVG(row_count) AS avg_rows
  FROM daily_loads
  GROUP BY source_system
  ORDER BY avg_rows > 10000;
  ```

---

### Question 2 — The `LEFT JOIN` Filter Trap
Consider the following tables:

*`fact_orders`*

| order_id | customer_id | amount |
|----------|-------------|--------|
| 1        | 101         | 100.00 |
| 2        | 102         | 200.00 |
| 3        | 999         | 50.00  |

*`dim_customers`*

| customer_id | country |
|-------------|---------|
| 101         | US      |
| 102         | CA      |

How many rows does the following query return?

```sql
SELECT o.order_id, c.country
FROM fact_orders AS o
LEFT JOIN dim_customers AS c
    ON o.customer_id = c.customer_id
WHERE c.country = 'US';
```

- **A.** 3 rows (`101 -> US`, `102 -> NULL`, `999 -> NULL`)
- **B.** 2 rows (`101 -> US`, `999 -> NULL`)
- **C.** 1 row (`101 -> US`)
- **D.** 0 rows

---

### Question 3 — Three-Valued Logic & `NOT IN`
Given a `dim_users` table containing `user_id` values `(1, 2, 3)` and an `excluded_users` table containing `user_id` values `(2, NULL)`:

```sql
SELECT user_id
FROM dim_users
WHERE user_id NOT IN (SELECT user_id FROM excluded_users);
```

What does this query return?

- **A.** `1, 3`
- **B.** `1, 2, 3`
- **C.** `1, 3, NULL`
- **D.** 0 rows (empty result set)

---

### Question 4 — Set Operations (`UNION` vs `UNION ALL` & `INTERSECT`)
Which statement about ANSI SQL set operations is **TRUE**?

- **A.** `UNION` is always faster than `UNION ALL` because it optimizes memory usage by discarding duplicates early.
- **B.** `UNION ALL` preserves duplicate rows and requires matching column counts and compatible types across `SELECT` branches.
- **C.** `INTERSECT` skips rows containing `NULL` values because `NULL = NULL` evaluates to `UNKNOWN`.
- **D.** `EXCEPT` returns rows that exist in either query but not both (symmetric difference).

---

### Question 5 — `NULLIF` & Sentinel Values
In a legacy CSV ingestion table `stg_metrics`, empty strings `''` and `0` denominators frequently appear. What does the following expression return when `clicks = 10` and `impressions = 0`?

```sql
clicks / NULLIF(impressions, 0)
```

- **A.** Raises a division-by-zero runtime error
- **B.** `0`
- **C.** `NULL`
- **D.** `10`

---

## Part B: Write the Query

### Question 6 — Orphan Record Detection (Anti-Join)
You are auditing referential integrity between `fact_shipments` and `dim_warehouses`. Write an ANSI SQL query to return all `shipment_id` and `warehouse_id` rows from `fact_shipments` that do **not** match any valid warehouse in `dim_warehouses`, **including** shipments whose `warehouse_id` is `NULL`. Ensure your query is safe against `NULL` values in `dim_warehouses.warehouse_id`.

*`fact_shipments`*

| shipment_id | warehouse_id | shipped_date |
|-------------|--------------|--------------|
| S100        | W1           | 2024-02-01   |
| S101        | W9           | 2024-02-01   |
| S102        | NULL         | 2024-02-02   |
| S103        | W2           | 2024-02-02   |

*`dim_warehouses`*

| warehouse_id | region |
|--------------|--------|
| W1           | US-East|
| W2           | EU-West|
| NULL         | Unknown|

---

### Question 7 — Fan-Out Diagnosis & Prevention
Your downstream finance dashboard reports inflated revenue after joining `fact_orders` with `dim_exchange_rates`.

*`fact_orders`*

| order_id | currency | order_date | amount |
|----------|----------|------------|--------|
| 1        | EUR      | 2024-03-01 | 100.00 |
| 2        | GBP      | 2024-03-01 | 200.00 |

*`dim_exchange_rates`*

| currency | rate_date  | usd_rate | source |
|----------|------------|----------|--------|
| EUR      | 2024-03-01 | 1.08     | feed_a |
| EUR      | 2024-03-01 | 1.09     | feed_b |
| GBP      | 2024-03-01 | 1.27     | feed_a |

1. Write a diagnostic query that detects the duplicate grain in `dim_exchange_rates` on `(currency, rate_date)`.
2. Write a fixed query that computes total USD revenue across all orders using an aggregated (deduplicated) exchange rate (`AVG(usd_rate)`) so no fan-out occurs.

---

### Question 8 — Two-Source Snapshot Reconciliation (`FULL OUTER JOIN` + `IS DISTINCT FROM`)
Compare yesterday's and today's user status snapshots to build a daily CDC audit report. Return every `user_id` present in either snapshot along with `prev_status`, `curr_status`, and a `change_type` column classified as:
- `'added'` — exists only in `snap_today`
- `'deleted'` — exists only in `snap_yesterday`
- `'updated'` — exists in both, and `status` changed (treating `NULL` vs non-`NULL` as a change, and `NULL` vs `NULL` as unchanged)
- `'unchanged'` — exists in both, and `status` is identical (including `NULL` vs `NULL`)

Order the result by `user_id`.

*`snap_yesterday`*

| user_id | status  |
|---------|---------|
| 1       | active  |
| 2       | pending |
| 3       | NULL    |
| 4       | active  |

*`snap_today`*

| user_id | status    |
|---------|-----------|
| 1       | active    |
| 2       | suspended |
| 3       | NULL      |
| 5       | active    |

---

### Question 9 — Safe Type Casting & Dirty Data Cleaning
You are building a staging model over `raw_payments`. Some rows contain whitespace-only strings, sentinel `'N/A'` strings, or malformed numeric strings.

*`raw_payments`*

| payment_id | amount_raw | currency_raw |
|------------|------------|--------------|
| P1         | 150.25     | USD          |
| P2         | N/A        | EUR          |
| P3         | 75.00      |              |
| P4         | -          | NULL         |
| P5         | 200.50     | GBP          |

Write a query that outputs:
- `payment_id`
- `amount_clean`: parsed as `DECIMAL(10, 2)` safely (`NULL` if unparseable, without failing the query)
- `currency_clean`: normalized currency where empty string `''` or `NULL` becomes `'UNKNOWN'`
- `is_amount_parse_error`: `TRUE` if `amount_raw` is non-NULL (and not empty) yet failed numeric parsing, otherwise `FALSE`

*(You may use `TRY_CAST` / `SAFE_CAST`, or an ANSI `CASE` guard if your dialect lacks `TRY_CAST`.)*

---

### Question 10 — Semi-Join & Post-Aggregation Filtering
Given `dim_accounts` and `pipeline_runs`, write a query to return each `account_id` and `account_name` for `'enterprise'` tier accounts that:
1. Have had **at least one** `'failed'` run (without duplicating account rows if there are multiple failures), **AND**
2. Have an overall average `duration_sec` strictly greater than `200` seconds across all their runs.

*`dim_accounts`*

| account_id | account_name | tier       |
|------------|--------------|------------|
| A1         | Acme Corp    | enterprise |
| A2         | Beta Labs    | starter    |
| A3         | Globex Inc   | enterprise |
| A4         | Initech      | enterprise |

*`pipeline_runs`*

| run_id | account_id | status  | duration_sec |
|--------|------------|---------|--------------|
| 1      | A1         | failed  | 300          |
| 2      | A1         | failed  | 250          |
| 3      | A2         | failed  | 500          |
| 4      | A3         | success | 400          |
| 5      | A4         | failed  | 100          |
| 6      | A4         | success | 150          |
