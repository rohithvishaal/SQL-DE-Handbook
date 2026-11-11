# Practice Exercises: Quizzes & Worked Solutions

> [!IMPORTANT]
> This directory contains **5 module-aligned exercise sets** combining multiple-choice diagnostics, realistic Data Engineering query-writing tasks, and slow-query refactoring drills. Instant right/wrong option checks and worked explanations live directly inside each quiz's **Explanation** tab.

---

## Exercise Module Index

| Module | Difficulty | Interactive Quiz | Companion Cheat Sheet | Topics Covered |
|---|---|---|---|---|
| **01 — Foundations & Core Syntax** | 🟢 Beginner – Intermediate | [01 Quiz](01-foundations/quiz.md) | [Module 1](../cheatsheets/01-foundations-syntax.md) | Execution order (`WHERE` vs. `HAVING`), `LEFT JOIN` filter traps, fan-out diagnosis, orphan anti-joins, set operations, 3-valued `NULL` / `NOT IN`, `NULLIF`, `IS DISTINCT FROM`, `TRY_CAST` |
| **02 — Window Functions & CTEs** | 🟡 Intermediate | [02 Quiz](02-window-functions/quiz.md) | [Module 2](../cheatsheets/02-window-functions.md) | `ROW_NUMBER` vs. `RANK` vs. `DENSE_RANK`, `NTILE`, `LAST_VALUE()` frame trap, `ROWS` vs. `RANGE` sliding windows, `LAG`/`FIRST_VALUE`, `QUALIFY` portability, chained & recursive CTEs with cycle protection |
| **03 — Production DE Patterns** | 🟡 Intermediate – Hard | [03 Quiz](03-de-patterns/quiz.md) | [Module 3](../cheatsheets/03-de-patterns.md) | Window-based deduplication & late arrivals, CDC & SCD Type 1/2, gaps & islands streaks, 30-min sessionization, JSON/array flattening, idempotent `MERGE INTO` & watermarks, calendar spines |
| **04 — Cloud DW Dialect Nuances** | 🟡 Intermediate – Hard | [04 Quiz](04-cloud-dw/quiz.md) | [Module 4](../cheatsheets/04-cloud-dw-matrix.md) | Cross-engine syntax across ANSI/DuckDB, Snowflake, BigQuery & Databricks: `QUALIFY` migration, JSON path extraction, `UNNEST`/`FLATTEN`/`EXPLODE` null preservation, `MERGE` deletes, safe division, string agg, date arithmetic, HLL sketches |
| **05 — Performance & Anti-Patterns** | 🔴 Hard | [05 Quiz](05-performance/quiz.md) | [Module 5](../cheatsheets/05-performance-tuning.md) | Diagnosing `EXPLAIN ANALYZE` / Query Profiles, non-SARGable predicates & partition pruning, small-files compaction, silent fan-out vs. `DISTINCT`, key salting for skew, implicit casts, CTE materialization, stale stats & join strategies |

---

## Topic Summaries by Module

### [01 — Foundations & Core Operations](01-foundations/quiz.md) (`🟢 Beginner – Intermediate`)
Tests the subtle SQL behaviors that cause silent data loss or inflated metrics in production pipelines: `WHERE` vs. `HAVING`, turning a `LEFT JOIN` into an implicit `INNER JOIN`, `NOT IN` returning zero rows when `NULL` is present, reconciling snapshots with `FULL OUTER JOIN` + `IS DISTINCT FROM`, and cleaning dirty source strings safely.

### [02 — Window Functions & CTEs](02-window-functions/quiz.md) (`🟡 Intermediate`)
Covers deterministic deduplication, avoiding the default `LAST_VALUE()` frame trap, choosing `ROWS BETWEEN` vs. `RANGE BETWEEN` when timestamps have ties or gaps, converting `QUALIFY` to portable ANSI subqueries, and writing cycle-safe recursive CTEs for lineage/impact graphs.

### [03 — Production DE Patterns](03-de-patterns/quiz.md) (`🟡 Intermediate – Hard`)
Focuses on situational data engineering scenarios: breaking ties in CDC streams, managing `valid_from` / `valid_to` / `is_current` intervals for SCD Type 2, detecting consecutive activity islands, splitting event streams into inactivity-bounded sessions, unnesting semi-structured payloads, and writing watermarked idempotent upserts.

### [04 — Cloud Data Warehouse Nuances](04-cloud-dw/quiz.md) (`🟡 Intermediate – Hard`)
Challenges you to migrate queries accurately between **ANSI/DuckDB**, **Snowflake**, **Google BigQuery**, and **Databricks (Spark SQL)** — catching silent traps like `EXPLODE` dropping empty/NULL arrays (vs. `EXPLODE_OUTER`), `SAFE_DIVIDE` changing downstream `AVG()` denominators, and dialect-specific JSON or date functions.

### [05 — Query Performance & Optimization](05-performance/quiz.md) (`🔴 Hard`)
Shifts from *correctness* to *execution cost*: spotting memory spills and skewed joins in query plans, rewriting `WHERE YEAR(dt) = ...` for partition pruning, salting hot join keys, removing redundant `SELECT DISTINCT` band-aids, fixing implicit cast bottlenecks, and controlling CTE evaluation.

---

## How to Study With These Exercises

1. **Read the matching cheat sheet first** — use the links in the table above to review syntax and gotchas.
2. **Answer cold before opening the Explanation tab** — pick an option or write your SQL on paper / against an inline test dataset first.
3. **Verify edge cases explicitly** — check what happens with `NULL`s, empty sets, duplicate keys, ties in `ORDER BY`, and zero denominators.
4. **Compare reasoning in the Explanation tab** — focus not just on the final query, but on *why* alternative answers fail or perform poorly.

---

## Local DuckDB / CLI Tip

> [!TIP]
> You can test almost any "Write the Query" exercise in seconds using the **DuckDB CLI** without creating permanent tables — just wrap the question's markdown sample table in a `WITH ... AS (VALUES ...)` CTE or load a scratch `.sql` file via `.read`.

```bash
# Start an ephemeral in-memory DuckDB session
duckdb
```

```sql
-- Enable clean box tables and execution timing inside the DuckDB CLI
.mode box
.timer on

-- Example: test an exercise's sample input inline with a VALUES CTE
WITH fact_orders (order_id, customer_id, amount) AS (
    VALUES
        (1, 101, 100.00),
        (2, 102, 200.00),
        (3, 999,  50.00)
),
dim_customers (customer_id, country) AS (
    VALUES
        (101, 'US'),
        (102, 'CA')
)
SELECT o.order_id, c.country
FROM fact_orders AS o
LEFT JOIN dim_customers AS c
    ON o.customer_id = c.customer_id
WHERE c.country = 'US';

-- For Module 05 exercises, inspect the local physical plan with:
EXPLAIN ANALYZE
SELECT customer_id, SUM(amount) AS total_amount
FROM (VALUES (101, 100.00), (101, 25.00), (102, 200.00)) AS t(customer_id, amount)
GROUP BY customer_id;
```

- Save your scratch solution to a file (for example `scratch.sql`) and run `.read scratch.sql` inside the DuckDB prompt, or run `duckdb < scratch.sql` from your terminal.
- To practice on multi-table datasets right away, load any schema and seed file from [`../projects/`](../projects/README.md).

---

## Continue Learning

- [Handbook Home](../README.md)
- [Module 6: FAANG / Big Tech Interview Masterclass](../interviews/README.md)
- [Capstone SQL Projects](../projects/README.md)
