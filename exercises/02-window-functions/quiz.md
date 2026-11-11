# Module 2 Quiz: Analytical SQL, Window Functions & CTEs

Test your understanding of ranking functions, value functions, window frames (`ROWS` vs `RANGE`), chained and recursive CTEs, and filtering window results.

---

## Part A: Multiple Choice

### Question 1 — Ranking Functions (`ROW_NUMBER`, `RANK`, `DENSE_RANK`)
Given the following `scores` rows sorted by `revenue DESC`: `(500, 500, 400, 300)`. What rank values are assigned to the `400` row by `ROW_NUMBER()`, `RANK()`, and `DENSE_RANK()` respectively?

- **A.** `3, 3, 2`
- **B.** `3, 2, 2`
- **C.** `2, 3, 2`
- **D.** `3, 3, 3`

---

### Question 2 — The `LAST_VALUE()` Default Frame Trap
Consider `runs`:

| run_id | duration_sec |
|--------|--------------|
| 1      | 120          |
| 2      | 95           |
| 3      | 200          |

What does the following query return for the `last_dur` column across the three rows (`run_id` 1, 2, 3)?

```sql
SELECT
    run_id,
    LAST_VALUE(duration_sec) OVER (ORDER BY run_id) AS last_dur
FROM runs
ORDER BY run_id;
```

- **A.** `200, 200, 200`
- **B.** `120, 95, 200`
- **C.** `NULL, NULL, 200`
- **D.** `120, 120, 120`

---

### Question 3 — `ROWS BETWEEN` vs `RANGE BETWEEN`
Consider `daily_sales`:

| sale_date  | amount |
|------------|--------|
| 2024-01-01 | 50     |
| 2024-01-02 | 100    |
| 2024-01-02 | 150    |

What value does `running_total` show on the **second row** (`sale_date = 2024-01-02`, `amount = 100`) if you omit the frame clause and write `SUM(amount) OVER (ORDER BY sale_date)`?

- **A.** `100`
- **B.** `150`
- **C.** `300`
- **D.** Raises a syntax error because a frame clause is mandatory with `SUM()`

---

### Question 4 — Filtering Window Results & Portability
Which statement about filtering on window function results is **TRUE**?

- **A.** You can filter a `ROW_NUMBER()` expression directly in the `WHERE` clause in ANSI SQL as long as you give it a column alias in `SELECT`.
- **B.** `HAVING` filters window function results before `SELECT` runs.
- **C.** `QUALIFY` is part of the ANSI SQL standard and works identically across PostgreSQL, MySQL, Snowflake, and BigQuery.
- **D.** Wrapping the window calculation in a CTE or subquery and filtering in the outer `WHERE` clause is portable across all modern ANSI SQL engines.

---

### Question 5 — Recursive CTEs & Cycle Protection
You are querying a graph table `edges(src, dst)` using a `WITH RECURSIVE` CTE that computes `depth + 1` on each hop. One row pair creates a cycle: `A -> B` and `B -> A`. What happens if you omit a depth/cycle limit?

- **A.** The SQL engine automatically detects the cycle and stops after 1 loop with `UNION ALL`.
- **B.** Changing `UNION ALL` to `UNION` always stops infinite recursion even when `depth` is part of the `SELECT` list.
- **C.** The query enters infinite recursion (until hitting the engine's max recursion limit or exhausting memory) because `(depth + 1)` makes every iteration's row distinct.
- **D.** The anchor query returns 0 rows.

---

## Part B: Write the Query

### Question 6 — Deterministic CDC Deduplication
You have a Change Data Capture (CDC) landing table `raw_cdc_events`. Multiple updates can arrive within the same second, causing ties on `updated_at`. Write an ANSI SQL query (using a CTE and `ROW_NUMBER()`) to return only the **latest** record per `entity_id`, breaking `updated_at` ties deterministically by selecting the **highest** `event_id`. Order the output by `entity_id`.

*(Bonus: Also show how this looks using `QUALIFY` for Snowflake/BigQuery/DuckDB.)*

*`raw_cdc_events`*

| event_id | entity_id | op     | updated_at          |
|----------|-----------|--------|---------------------|
| 10       | U1        | insert | 2024-04-01 10:00:00 |
| 11       | U1        | update | 2024-04-01 10:05:00 |
| 12       | U1        | update | 2024-04-01 10:05:00 |
| 20       | U2        | insert | 2024-04-01 09:00:00 |
| 21       | U2        | delete | 2024-04-01 11:00:00 |

---

### Question 7 — Pipeline State Transitions & Reference Values (`LAG`, `FIRST_VALUE`, `LAST_VALUE`)
Given `pipeline_runs`, write a query ordered by `pipeline_name, run_seq` that outputs for every row:
- `run_id`, `pipeline_name`, `run_seq`, `status`, `duration_sec`
- `prev_status`: status of the previous run for the same `pipeline_name` (use `'NONE'` if it is the first run)
- `status_changed`: `TRUE` if there was a previous run and `status <> prev_status`, otherwise `FALSE`
- `first_run_duration`: `duration_sec` of the earliest run for that `pipeline_name`
- `latest_run_duration`: `duration_sec` of the most recent run for that `pipeline_name`

*`pipeline_runs`*

| run_id | pipeline_name | run_seq | status  | duration_sec |
|--------|---------------|---------|---------|--------------|
| 1      | etl_sales     | 1       | success | 100          |
| 2      | etl_sales     | 2       | failed  | 40           |
| 3      | etl_sales     | 3       | failed  | 55           |
| 4      | etl_sales     | 4       | success | 120          |
| 5      | etl_users     | 1       | success | 80           |

---

### Question 8 — Running Totals, Moving Averages & `NTILE`
Given `daily_ingestion` for the `'events'` pipeline, write a query ordered by `ingest_date` that computes:
- `ingest_date`
- `rows_loaded`
- `cumulative_rows`: running sum of `rows_loaded` (using physical row framing)
- `moving_avg_3d`: 3-row moving average of `rows_loaded` (current row and 2 preceding rows), rounded to 2 decimal places
- `volume_half`: `NTILE(2)` bucket dividing the days into top half (`1`) and bottom half (`2`) by `rows_loaded DESC`

*`daily_ingestion`*

| pipeline_name | ingest_date | rows_loaded |
|---------------|-------------|-------------|
| events        | 2024-05-01  | 1000        |
| events        | 2024-05-02  | 2000        |
| events        | 2024-05-03  | 3000        |
| events        | 2024-05-04  | 4000        |

---

### Question 9 — Chained CTEs & Sliding 7-Day Time Window with Gaps
Your cloud billing table `raw_cloud_costs` has multiple line items per day and missing dates when no usage occurred. Write a query using **chained CTEs** to:
1. Aggregate `raw_cloud_costs` to the `(charge_date, service)` daily grain (`daily_cost`).
2. Calculate `rolling_7d_cost` per `service` using a true time-based sliding window spanning the **7 days preceding** `charge_date` through `charge_date` (`RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW`).

Order the output by `service, charge_date`.

*`raw_cloud_costs`*

| charge_date | service | cost_usd |
|-------------|---------|----------|
| 2024-06-01  | compute | 100.00   |
| 2024-06-01  | compute | 50.00    |
| 2024-06-03  | compute | 200.00   |
| 2024-06-08  | compute | 300.00   |
| 2024-06-10  | compute | 100.00   |

---

### Question 10 — Recursive CTE for Downstream Impact Analysis
Given a DAG dependency table `dag_dependencies`, write a `WITH RECURSIVE` query to identify every downstream task impacted if `'extract_orders'` fails.
- Start from `upstream_task = 'extract_orders'` (hop `1` for direct dependents).
- Include a cycle-safety guard (`hops < 20`).
- If a downstream task is reachable through multiple paths, return it **once** with its minimum `hops` distance (`MIN(hops)`).
- Order the final result by `hops ASC, task_name ASC`.

*`dag_dependencies`*

| upstream_task  | downstream_task |
|----------------|-----------------|
| extract_orders | stg_orders      |
| stg_orders     | fct_orders      |
| stg_orders     | fct_returns     |
| fct_orders     | rpt_revenue     |
| fct_returns    | rpt_revenue     |
| extract_users  | stg_users       |
