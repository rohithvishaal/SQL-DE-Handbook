# Computing Median and Percentiles Without Built-in Functions

## Difficulty

🟡 **Medium**

## Companies

Google, Meta, Amazon, Microsoft, Apple, LinkedIn

---

## Problem Statement

You are a data analyst at an e-commerce company. The product team wants to understand the **median order value** and the **25th and 75th percentile order values** for each product category. Your database engine does not support `PERCENTILE_CONT`, `MEDIAN()`, or any built-in percentile functions. You must compute these statistics using only basic window functions and aggregations.

This is a classic interview question that tests your understanding of how percentile calculations work under the hood — not just calling a function, but implementing the logic yourself.

---

## Schema DDL

```sql
CREATE TABLE orders (
    order_id     INT PRIMARY KEY,
    category     VARCHAR(50),
    order_value  DECIMAL(10,2),
    order_date   DATE
);

INSERT INTO orders (order_id, category, order_value, order_date) VALUES
(1,  'Electronics', 120.00, '2024-01-05'),
(2,  'Electronics', 250.00, '2024-01-08'),
(3,  'Electronics', 89.00,  '2024-01-12'),
(4,  'Electronics', 340.00, '2024-01-15'),
(5,  'Electronics', 175.00, '2024-01-20'),
(6,  'Electronics', 410.00, '2024-01-22'),
(7,  'Electronics', 55.00,  '2024-01-25'),
(8,  'Clothing',    45.00,  '2024-01-03'),
(9,  'Clothing',    78.00,  '2024-01-06'),
(10, 'Clothing',    120.00, '2024-01-10'),
(11, 'Clothing',    35.00,  '2024-01-14'),
(12, 'Clothing',    92.00,  '2024-01-18'),
(13, 'Clothing',    65.00,  '2024-01-21'),
(14, 'Books',       15.00,  '2024-01-02'),
(15, 'Books',       22.00,  '2024-01-09'),
(16, 'Books',       18.00,  '2024-01-13'),
(17, 'Books',       30.00,  '2024-01-17'),
(18, 'Books',       12.00,  '2024-01-23');
```

---

## Sample Input

**orders**

| order_id | category    | order_value | order_date |
|----------|-------------|-------------|------------|
| 1        | Electronics | 120.00      | 2024-01-05 |
| 2        | Electronics | 250.00      | 2024-01-08 |
| 3        | Electronics | 89.00       | 2024-01-12 |
| 4        | Electronics | 340.00      | 2024-01-15 |
| 5        | Electronics | 175.00      | 2024-01-20 |
| 6        | Electronics | 410.00      | 2024-01-22 |
| 7        | Electronics | 55.00       | 2024-01-25 |
| 8        | Clothing    | 45.00       | 2024-01-03 |
| 9        | Clothing    | 78.00       | 2024-01-06 |
| 10       | Clothing    | 120.00      | 2024-01-10 |
| 11       | Clothing    | 35.00       | 2024-01-14 |
| 12       | Clothing    | 92.00       | 2024-01-18 |
| 13       | Clothing    | 65.00       | 2024-01-21 |
| 14       | Books       | 15.00       | 2024-01-02 |
| 15       | Books       | 22.00       | 2024-01-09 |
| 16       | Books       | 18.00       | 2024-01-13 |
| 17       | Books       | 30.00       | 2024-01-17 |
| 18       | Books       | 12.00       | 2024-01-23 |

---

## Expected Output

| category    | p25    | median | p75    |
|-------------|--------|--------|--------|
| Books       | 15.00  | 18.00  | 22.00  |
| Clothing    | 50.00  | 71.50  | 88.50  |
| Electronics | 104.50 | 175.00 | 295.00 |

> [!NOTE]
> Using standard `PERCENTILE_CONT` linear interpolation (`pos = 1 + (cnt - 1) * p`):
> - **Books** (`cnt = 5`): sorted `[12, 15, 18, 22, 30]` -> `p25` at pos `2.0` (`15.00`), `median` at pos `3.0` (`18.00`), `p75` at pos `4.0` (`22.00`).
> - **Clothing** (`cnt = 6`): sorted `[35, 45, 65, 78, 92, 120]` -> `p25` at pos `2.25` (`45 + 0.25 * (65 - 45) = 50.00`), `median` at pos `3.5` (`(65 + 78) / 2 = 71.50`), `p75` at pos `4.75` (`78 + 0.75 * (92 - 78) = 88.50`).
> - **Electronics** (`cnt = 7`): sorted `[55, 89, 120, 175, 250, 340, 410]` -> `p25` at pos `2.5` (`(89 + 120) / 2 = 104.50`), `median` at pos `4.0` (`175.00`), `p75` at pos `5.5` (`(250 + 340) / 2 = 295.00`).

---

## Brute Force Solution

**Approach: Separate CTEs per percentile with `ROW_NUMBER()` and `COUNT()`**

The idea is to rank each row within its category, count the total rows per category, and then build separate CTEs for each percentile (`p25`, `median`, `p75`) before joining them together.

```sql
WITH ranked AS (
    SELECT
        category,
        order_value,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY order_value, order_id) AS rn,
        COUNT(*)     OVER (PARTITION BY category)                               AS cnt
    FROM orders
),
median_calc AS (
    SELECT
        category,
        ROUND(AVG(order_value), 2) AS median_val
    FROM ranked
    WHERE rn IN (FLOOR((cnt + 1) / 2.0), CEIL((cnt + 1) / 2.0))
    GROUP BY category
),
p25_calc AS (
    SELECT
        r_lo.category,
        ROUND(
            r_lo.order_value + (r_hi.order_value - r_lo.order_value) * ((1 + (r_lo.cnt - 1) * 0.25) - FLOOR(1 + (r_lo.cnt - 1) * 0.25)),
            2
        ) AS p25_val
    FROM ranked r_lo
    JOIN ranked r_hi
      ON r_lo.category = r_hi.category
     AND r_lo.rn = FLOOR(1 + (r_lo.cnt - 1) * 0.25)
     AND r_hi.rn = CEIL(1 + (r_hi.cnt - 1) * 0.25)
),
p75_calc AS (
    SELECT
        r_lo.category,
        ROUND(
            r_lo.order_value + (r_hi.order_value - r_lo.order_value) * ((1 + (r_lo.cnt - 1) * 0.75) - FLOOR(1 + (r_lo.cnt - 1) * 0.75)),
            2
        ) AS p75_val
    FROM ranked r_lo
    JOIN ranked r_hi
      ON r_lo.category = r_hi.category
     AND r_lo.rn = FLOOR(1 + (r_lo.cnt - 1) * 0.75)
     AND r_hi.rn = CEIL(1 + (r_hi.cnt - 1) * 0.75)
)
SELECT
    m.category,
    p25.p25_val   AS p25,
    m.median_val  AS median,
    p75.p75_val   AS p75
FROM median_calc m
JOIN p25_calc p25 ON m.category = p25.category
JOIN p75_calc p75 ON m.category = p75.category
ORDER BY m.category;
```

**Explanation:**
1. Rank each order value within its category using `ROW_NUMBER()` (adding `order_id` as a deterministic tie-breaker).
2. Calculate the total count `cnt` per category.
3. For the median, pick the middle 1 (odd `cnt`) or 2 (even `cnt`) rows and take `AVG(order_value)`.
4. For `p25` and `p75`, self-join `ranked` to match the `FLOOR` and `CEIL` rows around position `1 + (cnt - 1) * p` and linearly interpolate between them.
5. Join all three percentile CTEs together by `category`.

**Downsides:** Repetitive CTEs and multiple self-joins on `ranked` (one self-join per percentile). Hard to maintain and scales poorly as more percentiles (e.g., P90, P95, P99) are requested.

---

## Optimal Solution

**Approach: Single pass with `ROW_NUMBER()` + conditional aggregation interpolation**

```sql
WITH ranked AS (
    SELECT
        category,
        order_value,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY order_value, order_id) AS rn,
        COUNT(*)     OVER (PARTITION BY category)                               AS cnt
    FROM orders
),
positions AS (
    SELECT
        category,
        order_value,
        rn,
        1.0 + (cnt - 1) * 0.25 AS pos_25,
        1.0 + (cnt - 1) * 0.50 AS pos_50,
        1.0 + (cnt - 1) * 0.75 AS pos_75
    FROM ranked
)
SELECT
    category,
    ROUND(
        MAX(CASE WHEN rn = FLOOR(pos_25) THEN order_value END)
      + (MAX(CASE WHEN rn = CEIL(pos_25) THEN order_value END)
       - MAX(CASE WHEN rn = FLOOR(pos_25) THEN order_value END))
      * (MAX(pos_25) - FLOOR(MAX(pos_25))),
        2
    ) AS p25,
    ROUND(
        MAX(CASE WHEN rn = FLOOR(pos_50) THEN order_value END)
      + (MAX(CASE WHEN rn = CEIL(pos_50) THEN order_value END)
       - MAX(CASE WHEN rn = FLOOR(pos_50) THEN order_value END))
      * (MAX(pos_50) - FLOOR(MAX(pos_50))),
        2
    ) AS median,
    ROUND(
        MAX(CASE WHEN rn = FLOOR(pos_75) THEN order_value END)
      + (MAX(CASE WHEN rn = CEIL(pos_75) THEN order_value END)
       - MAX(CASE WHEN rn = FLOOR(pos_75) THEN order_value END))
      * (MAX(pos_75) - FLOOR(MAX(pos_75))),
        2
    ) AS p75
FROM positions
GROUP BY category
ORDER BY category;
```

**Why this is better:**
1. **Single CTE + single `GROUP BY`** — eliminates all self-joins and repeated CTE scans.
2. **Exact linear interpolation formula (`val_lo + (val_hi - val_lo) * frac`)** handles both integer and fractional positions safely without edge-case branches: when `pos` is an integer (`FLOOR(pos) = CEIL(pos)`), the fractional offset `pos - FLOOR(pos)` is `0`, so the formula cleanly returns `val_lo`.
3. **Matches `PERCENTILE_CONT`** — computing `pos = 1 + (cnt - 1) * p` produces identical results to ANSI `PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY order_value)`.
4. **Easily extensible** — adding P90 or P99 requires only one extra `pos_XX` column and one extra `ROUND(...)` expression in the final `SELECT`.

> [!WARNING]
> **Common pitfall**: Using `NTILE(4)` to compute quartiles. `NTILE` divides rows into N buckets of approximately equal size, but it does **not** compute percentile values. For 7 rows, `NTILE(4)` gives buckets of sizes 2, 2, 2, 1 — which doesn't correspond to the 25th percentile position.

---

## Interviewer Follow-Up Questions

### 1. "How would you handle NULL values in order_value?"

Filter them out before ranking, or decide on a business rule. Typically:
```sql
FROM orders
WHERE order_value IS NOT NULL
```
Alternatively, if NULLs should be treated as zero, use `COALESCE(order_value, 0)`.

### 2. "What if you need the exact same result as PERCENTILE_CONT with linear interpolation?"

The optimal solution already implements linear interpolation identical to `PERCENTILE_CONT`. The general formula for position `h = (N - 1) * p + 1` (1-indexed) requires slight adjustment. Verify against:
```sql
-- Validation query (if your engine supports it)
SELECT category,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY order_value) AS p25,
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY order_value) AS median,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY order_value) AS p75
FROM orders
GROUP BY category;
```

### 3. "How would you compute an approximate median on a billion-row table?"

Use **approximate percentile functions** if available (`APPROX_PERCENTILE` in Spark/Presto, `APPROXIMATE_PERCENTILE` in BigQuery). Alternatively, use a **sampling approach**: compute the median on a random 1% sample. For exact results on massive data, consider **t-digest** or **KLL sketch** algorithms available in many modern engines.

---

## Key Takeaways

- 📌 **Median = the 50th percentile** — the value separating the higher half from the lower half of the data
- 📌 The **ROW_NUMBER + conditional MAX** pattern lets you "pick" specific ranked rows without self-joins
- 📌 **Linear interpolation** unifies odd/even count handling: `value_lo * (1 - frac) + value_hi * frac`
- 📌 `NTILE(N)` is **not** the same as computing the Nth percentile — a common interview trap
- 📌 For production systems with massive data, prefer **approximate percentile** functions or **sketches** over exact computation
- 📌 Always clarify how to handle NULLs and ties before coding
