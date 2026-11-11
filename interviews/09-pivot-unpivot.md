# 09 — Dynamic Pivot / Unpivot for Reporting

## Difficulty

**Medium**

## Companies

Microsoft · Amazon · Salesforce · Oracle

---

## Problem Statement

You are a data engineer building reporting pipelines for a SaaS analytics platform. The product team stores **quarterly revenue by region** in a normalized (tall/long) format, but the executive dashboard requires a **pivoted (wide) format** where each region becomes its own column. Conversely, a downstream ML pipeline needs the data **unpivoted** back to long format from a legacy wide table.

Write two queries:
1. **Pivot**: Transform the long-format revenue table into a wide-format report with one row per quarter and one column per region.
2. **Unpivot**: Transform a wide-format table (one column per metric) back into a normalized long-format table.

---

## Schema DDL

```sql
-- Long-format revenue table (for Pivot)
CREATE TABLE quarterly_revenue (
    quarter     VARCHAR(10) NOT NULL,
    region      VARCHAR(20) NOT NULL,
    revenue     DECIMAL(12,2) NOT NULL,
    PRIMARY KEY (quarter, region)
);

INSERT INTO quarterly_revenue (quarter, region, revenue) VALUES
('2024-Q1', 'North America', 1250000.00),
('2024-Q1', 'Europe',        890000.00),
('2024-Q1', 'Asia Pacific',  670000.00),
('2024-Q1', 'Latin America', 340000.00),
('2024-Q2', 'North America', 1380000.00),
('2024-Q2', 'Europe',        920000.00),
('2024-Q2', 'Asia Pacific',  750000.00),
('2024-Q2', 'Latin America', 365000.00),
('2024-Q3', 'North America', 1420000.00),
('2024-Q3', 'Europe',        985000.00),
('2024-Q3', 'Asia Pacific',  810000.00),
('2024-Q3', 'Latin America', 390000.00),
('2024-Q4', 'North America', 1560000.00),
('2024-Q4', 'Europe',        1050000.00),
('2024-Q4', 'Asia Pacific',  880000.00),
('2024-Q4', 'Latin America', 420000.00);

-- Wide-format metrics table (for Unpivot)
CREATE TABLE product_metrics_wide (
    product_id    INT PRIMARY KEY,
    product_name  VARCHAR(50) NOT NULL,
    page_views    INT NOT NULL,
    signups       INT NOT NULL,
    purchases     INT NOT NULL,
    refunds       INT NOT NULL
);

INSERT INTO product_metrics_wide (product_id, product_name, page_views, signups, purchases, refunds) VALUES
(1, 'Widget Pro',     15000, 3200, 1800, 45),
(2, 'Widget Lite',    22000, 5100, 2400, 120),
(3, 'Widget Max',     8500,  1900, 950,  30),
(4, 'Widget Mini',    31000, 7200, 3600, 200),
(5, 'Widget Ultra',   12000, 2800, 1500, 65);
```

---

## Sample Input

### quarterly_revenue (long format — for Pivot)

| quarter | region        | revenue     |
|---------|---------------|-------------|
| 2024-Q1 | North America | 1250000.00  |
| 2024-Q1 | Europe        | 890000.00   |
| 2024-Q1 | Asia Pacific  | 670000.00   |
| 2024-Q1 | Latin America | 340000.00   |
| 2024-Q2 | North America | 1380000.00  |
| 2024-Q2 | Europe        | 920000.00   |
| 2024-Q2 | Asia Pacific  | 750000.00   |
| 2024-Q2 | Latin America | 365000.00   |
| 2024-Q3 | North America | 1420000.00  |
| 2024-Q3 | Europe        | 985000.00   |
| 2024-Q3 | Asia Pacific  | 810000.00   |
| 2024-Q3 | Latin America | 390000.00   |
| 2024-Q4 | North America | 1560000.00  |
| 2024-Q4 | Europe        | 1050000.00  |
| 2024-Q4 | Asia Pacific  | 880000.00   |
| 2024-Q4 | Latin America | 420000.00   |

### product_metrics_wide (wide format — for Unpivot)

| product_id | product_name | page_views | signups | purchases | refunds |
|------------|-------------|------------|---------|-----------|---------|
| 1          | Widget Pro  | 15000      | 3200    | 1800      | 45      |
| 2          | Widget Lite | 22000      | 5100    | 2400      | 120     |
| 3          | Widget Max  | 8500       | 1900    | 950       | 30      |
| 4          | Widget Mini | 31000      | 7200    | 3600      | 200     |
| 5          | Widget Ultra| 12000      | 2800    | 1500      | 65      |

---

## Expected Output

### Pivot Result (long → wide)

| quarter | north_america | europe     | asia_pacific | latin_america |
|---------|---------------|------------|-------------|---------------|
| 2024-Q1 | 1250000.00    | 890000.00  | 670000.00   | 340000.00     |
| 2024-Q2 | 1380000.00    | 920000.00  | 750000.00   | 365000.00     |
| 2024-Q3 | 1420000.00    | 985000.00  | 810000.00   | 390000.00     |
| 2024-Q4 | 1560000.00    | 1050000.00 | 880000.00   | 420000.00     |

### Unpivot Result (wide → long)

| product_id | product_name | metric_name | metric_value |
|------------|-------------|-------------|-------------|
| 1          | Widget Pro  | page_views  | 15000       |
| 1          | Widget Pro  | signups     | 3200        |
| 1          | Widget Pro  | purchases   | 1800        |
| 1          | Widget Pro  | refunds     | 45          |
| 2          | Widget Lite | page_views  | 22000       |
| 2          | Widget Lite | signups     | 5100        |
| 2          | Widget Lite | purchases   | 2400        |
| 2          | Widget Lite | refunds     | 120         |
| ...        | ...         | ...         | ...         |

---

## Brute Force Solution

### Pivot: Multiple Subqueries

The most basic approach uses one subquery per region.

```sql
-- Brute Force Pivot: One subquery per region
SELECT
    q.quarter,
    (SELECT revenue FROM quarterly_revenue
     WHERE quarter = q.quarter AND region = 'North America') AS north_america,
    (SELECT revenue FROM quarterly_revenue
     WHERE quarter = q.quarter AND region = 'Europe') AS europe,
    (SELECT revenue FROM quarterly_revenue
     WHERE quarter = q.quarter AND region = 'Asia Pacific') AS asia_pacific,
    (SELECT revenue FROM quarterly_revenue
     WHERE quarter = q.quarter AND region = 'Latin America') AS latin_america
FROM (SELECT DISTINCT quarter FROM quarterly_revenue) q
ORDER BY q.quarter;
```

### Unpivot: UNION ALL per Column

```sql
-- Brute Force Unpivot: One SELECT per metric column
SELECT product_id, product_name, 'page_views' AS metric_name, page_views AS metric_value
FROM product_metrics_wide
UNION ALL
SELECT product_id, product_name, 'signups',    signups
FROM product_metrics_wide
UNION ALL
SELECT product_id, product_name, 'purchases',  purchases
FROM product_metrics_wide
UNION ALL
SELECT product_id, product_name, 'refunds',    refunds
FROM product_metrics_wide
ORDER BY product_id, metric_name;
```

### Step-by-Step Explanation

**Pivot**:
1. Get distinct quarters as the row axis.
2. For each quarter, run a scalar subquery to fetch each region's revenue.
3. Each subquery scans the table independently — **4 scans per quarter row** = very inefficient.

**Unpivot**:
1. Write one `SELECT` per metric column, hardcoding the metric name as a string literal.
2. `UNION ALL` combines them into a single long-format result.
3. Each `SELECT` scans the entire table — **4 full table scans**.

> **Drawback**: Both approaches scan the source table multiple times and do not scale well as the number of pivot categories or metric columns grows.

---

## Optimal Solution

### Pivot: Conditional Aggregation (CASE WHEN)

```sql
-- Optimal Pivot: CASE WHEN + GROUP BY (single scan)
SELECT
    quarter,
    SUM(CASE WHEN region = 'North America' THEN revenue ELSE 0 END) AS north_america,
    SUM(CASE WHEN region = 'Europe'        THEN revenue ELSE 0 END) AS europe,
    SUM(CASE WHEN region = 'Asia Pacific'  THEN revenue ELSE 0 END) AS asia_pacific,
    SUM(CASE WHEN region = 'Latin America' THEN revenue ELSE 0 END) AS latin_america
FROM quarterly_revenue
GROUP BY quarter
ORDER BY quarter;
```

### Unpivot: CROSS JOIN with Values List

```sql
-- Optimal Unpivot: CROSS JOIN UNNEST / VALUES (single scan)
SELECT
    p.product_id,
    p.product_name,
    m.metric_name,
    CASE m.metric_name
        WHEN 'page_views' THEN p.page_views
        WHEN 'signups'    THEN p.signups
        WHEN 'purchases'  THEN p.purchases
        WHEN 'refunds'    THEN p.refunds
    END AS metric_value
FROM product_metrics_wide p
CROSS JOIN (
    VALUES ('page_views'), ('signups'), ('purchases'), ('refunds')
) AS m(metric_name)
ORDER BY p.product_id, m.metric_name;
```

### Why This Is Better

| Aspect | Brute Force | Optimal |
|--------|------------|---------|
| **Table scans** | N scans (one per category/column) | **Single scan** of the source table |
| **Scalability** | Performance degrades linearly with # of categories | Constant — single pass regardless of category count |
| **Readability** | Many repeated subqueries / UNION ALL blocks | Compact, pattern-based approach |
| **Maintainability** | Adding a new region/metric requires another subquery/UNION | Adding a new region/metric is one line in the CASE |

> [!TIP]
> **Dialect-specific shortcuts**: Many engines offer native PIVOT/UNPIVOT syntax (SQL Server `PIVOT`, Oracle `UNPIVOT`, BigQuery `PIVOT()`, Snowflake `PIVOT()`). These compile down to the same conditional aggregation but offer cleaner syntax. Always know the ANSI CASE WHEN approach for portability.

---

## Interviewer Follow-Up Questions

1. **"What if the regions are not known ahead of time — how do you do a truly dynamic pivot?"**
   - In pure ANSI SQL, you cannot — column names must be fixed at parse time. The standard approach is **dynamic SQL**: query the distinct values first, build the `CASE WHEN` expressions as a string, then execute the generated query. In Python/dbt, you can use Jinja templating: `{% for region in regions %} SUM(CASE WHEN region = '{{ region }}' ...) {% endfor %}`. In BigQuery, use `SELECT * FROM ... PIVOT(SUM(revenue) FOR region IN (...))`.

2. **"How do you handle NULLs in the pivot — what if a region has no data for a quarter?"**
   - Use `COALESCE(SUM(CASE WHEN ...), 0)` to replace NULLs with 0. Be intentional: sometimes NULL is semantically meaningful (region doesn't operate that quarter) vs. 0 (operated but had zero revenue). Document the decision.

3. **"What is the performance impact of pivoting a table with 100 regions into 100 columns?"**
   - The single-scan approach remains O(n) regardless of column count, but the **output width** grows. At extreme widths (100+ columns), consider whether a pivoted table is the right model — columnar stores handle it well, but row-oriented stores may suffer from wide-row overhead. Often it is better to keep data in long format and let the BI tool (Tableau, Looker) handle the pivot at visualization time.

---

## Key Takeaways

- **Pivot (long → wide)**: Use `SUM(CASE WHEN category = 'X' THEN value END) … GROUP BY row_key` — this is the universal ANSI SQL pattern.
- **Unpivot (wide → long)**: Use `CROSS JOIN (VALUES (...)) AS m(name)` with a `CASE` expression, or `UNION ALL` (brute force).
- **Single scan** is the key performance win — conditional aggregation reads the table once regardless of how many categories you pivot.
- **Dynamic pivot** is not possible in static ANSI SQL; it requires dynamic SQL, stored procedures, or template engines (Jinja/dbt).
- **`ELSE 0`** vs **`ELSE NULL`**: In pivot SUM expressions, `ELSE 0` avoids NULLs; `ELSE NULL` (or omitting ELSE) preserves the distinction between "no data" and "zero."
- Always assess whether the **BI layer** should handle the pivot — databases are optimized for long-format storage, and pivoting at query time is often more flexible than materializing wide tables.
