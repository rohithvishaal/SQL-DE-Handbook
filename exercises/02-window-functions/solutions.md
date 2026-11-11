# Module 2 Solutions: Analytical SQL, Window Functions & CTEs

---

## Part A: Multiple Choice

### Question 1 — Ranking Functions (`ROW_NUMBER`, `RANK`, `DENSE_RANK`)
**Correct Answer:** **A** (`3, 3, 2`)

**Explanation:**
For `(500, 500, 400, 300)`:
- `ROW_NUMBER()` assigns unique sequential integers regardless of ties → `1, 2, 3, 4` (`400` gets **`3`**).
- `RANK()` gives ties the same rank and leaves gaps afterward → `1, 1, 3, 4` (`400` gets **`3`**).
- `DENSE_RANK()` gives ties the same rank with **no gaps** → `1, 1, 2, 3` (`400` gets **`2`**).

---

### Question 2 — The `LAST_VALUE()` Default Frame Trap
**Correct Answer:** **B** (`120, 95, 200`)

**Explanation:**
When `ORDER BY` is present in an `OVER (...)` clause without an explicit frame specification, SQL defaults to `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. Because `run_id` is unique, the "last row of the frame" at each step is just the **current row**, returning `120, 95, 200`. To get `200` for every row, you must specify `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`.

---

### Question 3 — `ROWS BETWEEN` vs `RANGE BETWEEN`
**Correct Answer:** **C** (`300`)

**Explanation:**
Omitting the frame clause defaults to `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. Because `RANGE` groups logical peers (rows with equal `ORDER BY` values), both `2024-01-02` rows share the exact same frame (`2024-01-01` + both `2024-01-02` rows), yielding `50 + 100 + 150 = 300`. If you wanted `150` on row 2 and `300` on row 3, you would explicitly write `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`.

---

### Question 4 — Filtering Window Results & Portability
**Correct Answer:** **D**

**Explanation:**
- **D is correct:** Wrapping the window function in a CTE or subquery lets the outer `WHERE` clause filter on the computed column in every ANSI-compliant SQL database.
- **A is wrong:** `WHERE` executes *before* window functions and `SELECT` aliases, so neither window functions nor `SELECT` aliases are valid in `WHERE`.
- **B is wrong:** `HAVING` filters grouped aggregates before `SELECT` / window evaluation.
- **C is wrong:** `QUALIFY` is **not** part of the ANSI SQL standard; it is supported by Snowflake, BigQuery, Databricks, and DuckDB, but rejected by PostgreSQL, MySQL, and SQL Server.

---

### Question 5 — Recursive CTEs & Cycle Protection
**Correct Answer:** **C**

**Explanation:**
Because `depth + 1` produces a brand-new row tuple on each iteration (`(B, 2)`, `(A, 3)`, `(B, 4)`, ...), even `UNION` (which only deduplicates identical complete rows) cannot terminate the loop. Without an explicit cycle guard (such as `WHERE depth < max_depth` or tracking visited node paths), `WITH RECURSIVE` loops until hitting the engine's recursion limit or running out of resources.

---

## Part B: Write the Query

### Question 6 — Deterministic CDC Deduplication

**Solution (ANSI SQL with CTE):**
```sql
WITH ranked_events AS (
    SELECT
        event_id,
        entity_id,
        op,
        updated_at,
        ROW_NUMBER() OVER (
            PARTITION BY entity_id
            ORDER BY updated_at DESC, event_id DESC
        ) AS rn
    FROM raw_cdc_events
)
SELECT
    event_id,
    entity_id,
    op,
    updated_at
FROM ranked_events
WHERE rn = 1
ORDER BY entity_id;
```

**`QUALIFY` Alternative (Snowflake / BigQuery / Databricks / DuckDB):**
```sql
SELECT
    event_id,
    entity_id,
    op,
    updated_at
FROM raw_cdc_events
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY entity_id
    ORDER BY updated_at DESC, event_id DESC
) = 1
ORDER BY entity_id;
```

**Expected Output:**

| event_id | entity_id | op     | updated_at          |
|----------|-----------|--------|---------------------|
| 12       | U1        | update | 2024-04-01 10:05:00 |
| 21       | U2        | delete | 2024-04-01 11:00:00 |

**Explanation:**
Adding `event_id DESC` as a secondary sort key inside `ORDER BY` makes `ROW_NUMBER()` completely deterministic when two events for `U1` share the timestamp `2024-04-01 10:05:00`. Without that tiebreaker, different pipeline runs could pick either `event_id = 11` or `event_id = 12`.

---

### Question 7 — Pipeline State Transitions & Reference Values (`LAG`, `FIRST_VALUE`, `LAST_VALUE`)

**Solution:**
```sql
WITH lagged AS (
    SELECT
        run_id,
        pipeline_name,
        run_seq,
        status,
        duration_sec,
        LAG(status, 1, 'NONE') OVER (
            PARTITION BY pipeline_name
            ORDER BY run_seq
        ) AS prev_status,
        FIRST_VALUE(duration_sec) OVER (
            PARTITION BY pipeline_name
            ORDER BY run_seq
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS first_run_duration,
        LAST_VALUE(duration_sec) OVER (
            PARTITION BY pipeline_name
            ORDER BY run_seq
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS latest_run_duration
    FROM pipeline_runs
)
SELECT
    run_id,
    pipeline_name,
    run_seq,
    status,
    duration_sec,
    prev_status,
    CASE
        WHEN prev_status <> 'NONE' AND status <> prev_status THEN TRUE
        ELSE FALSE
    END AS status_changed,
    first_run_duration,
    latest_run_duration
FROM lagged
ORDER BY pipeline_name, run_seq;
```

**Expected Output:**

| run_id | pipeline_name | run_seq | status  | duration_sec | prev_status | status_changed | first_run_duration | latest_run_duration |
|--------|---------------|---------|---------|--------------|-------------|----------------|--------------------|---------------------|
| 1      | etl_sales     | 1       | success | 100          | NONE        | FALSE          | 100                | 120                 |
| 2      | etl_sales     | 2       | failed  | 40           | success     | TRUE           | 100                | 120                 |
| 3      | etl_sales     | 3       | failed  | 55           | failed      | FALSE          | 100                | 120                 |
| 4      | etl_sales     | 4       | success | 120          | failed      | TRUE           | 100                | 120                 |
| 5      | etl_users     | 1       | success | 80           | NONE        | FALSE          | 80                 | 80                  |

**Explanation:**
- `LAG(status, 1, 'NONE')` safely supplies `'NONE'` for the boundary row (`run_seq = 1`) instead of `NULL`.
- Using a CTE (`lagged`) avoids repeating the `LAG(...)` expression inside the `CASE` statement for `status_changed`.
- Specifying `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` on `LAST_VALUE()` is mandatory so every row in `etl_sales` sees `120` instead of its own `duration_sec`.

---

### Question 8 — Running Totals, Moving Averages & `NTILE`

**Solution:**
```sql
SELECT
    ingest_date,
    rows_loaded,
    SUM(rows_loaded) OVER (
        PARTITION BY pipeline_name
        ORDER BY ingest_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_rows,
    ROUND(
        AVG(rows_loaded) OVER (
            PARTITION BY pipeline_name
            ORDER BY ingest_date
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
        2
    ) AS moving_avg_3d,
    NTILE(2) OVER (
        PARTITION BY pipeline_name
        ORDER BY rows_loaded DESC
    ) AS volume_half
FROM daily_ingestion
WHERE pipeline_name = 'events'
ORDER BY ingest_date;
```

**Expected Output:**

| ingest_date | rows_loaded | cumulative_rows | moving_avg_3d | volume_half |
|-------------|-------------|-----------------|---------------|-------------|
| 2024-05-01  | 1000        | 1000            | 1000.00       | 2           |
| 2024-05-02  | 2000        | 3000            | 1500.00       | 2           |
| 2024-05-03  | 3000        | 6000            | 2000.00       | 1           |
| 2024-05-04  | 4000        | 10000           | 3000.00       | 1           |

**Explanation:**
- Each window function can declare its own independent `ORDER BY` inside `OVER (...)` — `cumulative_rows` and `moving_avg_3d` sort chronologically by `ingest_date`, while `NTILE(2)` sorts by `rows_loaded DESC`.
- Notice that `2024-05-01` and `2024-05-02` have partial moving-average windows (1 and 2 rows respectively, instead of 3).

---

### Question 9 — Chained CTEs & Sliding 7-Day Time Window with Gaps

**Solution:**
```sql
WITH daily_costs AS (
    SELECT
        charge_date,
        service,
        SUM(cost_usd) AS daily_cost
    FROM raw_cloud_costs
    GROUP BY charge_date, service
),

rolling_costs AS (
    SELECT
        charge_date,
        service,
        daily_cost,
        SUM(daily_cost) OVER (
            PARTITION BY service
            ORDER BY charge_date
            RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
        ) AS rolling_7d_cost
    FROM daily_costs
)

SELECT
    charge_date,
    service,
    daily_cost,
    rolling_7d_cost
FROM rolling_costs
ORDER BY service, charge_date;
```

**Expected Output:**

| charge_date | service | daily_cost | rolling_7d_cost |
|-------------|---------|------------|-----------------|
| 2024-06-01  | compute | 150.00     | 150.00          |
| 2024-06-03  | compute | 200.00     | 350.00          |
| 2024-06-08  | compute | 300.00     | 650.00          |
| 2024-06-10  | compute | 100.00     | 600.00          |

**Explanation:**
- Stage 1 (`daily_costs`) rolls up the two `2024-06-01` line items (`100.00 + 50.00 = 150.00`), establishing a clean `(charge_date, service)` grain.
- Stage 2 uses `RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW` rather than `ROWS BETWEEN`:
  - On `2024-06-08`, `2024-06-08 - 7 days = 2024-06-01`, so `2024-06-01` (`150.00`), `2024-06-03` (`200.00`), and `2024-06-08` (`300.00`) sum to `650.00`.
  - On `2024-06-10`, `2024-06-10 - 7 days = 2024-06-03`, so `2024-06-01` drops out and `200.00 + 300.00 + 100.00 = 600.00`.
  - Using `ROWS` instead of `RANGE` would wrongly include `2024-06-01` on `2024-06-10` because of the missing dates!
- *(Dialect note: If `charge_date` is `DATE` and your engine requires `TIMESTAMP` for `INTERVAL` frames in `RANGE`, cast `CAST(charge_date AS TIMESTAMP)` inside `ORDER BY`.)*

---

### Question 10 — Recursive CTE for Downstream Impact Analysis

**Solution:**
```sql
WITH RECURSIVE impacted_tasks AS (
    -- Anchor: direct downstream dependents of extract_orders
    SELECT
        downstream_task AS task_name,
        1 AS hops
    FROM dag_dependencies
    WHERE upstream_task = 'extract_orders'

    UNION ALL

    -- Recursive: traverse further downstream with a cycle guard
    SELECT
        d.downstream_task AS task_name,
        i.hops + 1 AS hops
    FROM dag_dependencies AS d
    INNER JOIN impacted_tasks AS i
        ON d.upstream_task = i.task_name
    WHERE i.hops < 20
)
SELECT
    task_name,
    MIN(hops) AS hops
FROM impacted_tasks
GROUP BY task_name
ORDER BY hops ASC, task_name ASC;
```

**Expected Output:**

| task_name   | hops |
|-------------|------|
| stg_orders  | 1    |
| fct_orders  | 2    |
| fct_returns | 2    |
| rpt_revenue | 3    |

**Explanation:**
- The anchor selects direct children of `'extract_orders'` (`stg_orders` at `hops = 1`).
- The recursive member joins `dag_dependencies.upstream_task` to the previously discovered `impacted_tasks.task_name`, incrementing `hops`.
- `WHERE i.hops < 20` prevents infinite loops if a circular dependency is ever introduced into `dag_dependencies`.
- Because `rpt_revenue` has two paths (`stg_orders -> fct_orders -> rpt_revenue` and `stg_orders -> fct_returns -> rpt_revenue`), `GROUP BY task_name` with `MIN(hops)` collapses duplicates cleanly. (`extract_users -> stg_users` is excluded because it is not downstream of `extract_orders`.)
