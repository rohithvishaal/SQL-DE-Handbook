# Top N Products per Category with Ties and Percentiles

> Ranking, Dense Ranking, and Percentile Analysis

**Difficulty:** Medium

**Companies:** Amazon, Walmart, Instacart, DoorDash

---

## Problem Statement

You are a data analyst at an e-commerce company. The merchandising team wants a report showing the **top 3 best-selling products in each category by total revenue**, but with a twist: if two products have the same revenue they must share the same rank (i.e., handle ties properly), and all tied products must appear in the output even if that means more than 3 rows per category. Additionally, the team wants each product's **revenue percentile within its category** to understand relative performance. This is a classic ranking problem that tests your ability to choose between `ROW_NUMBER`, `RANK`, and `DENSE_RANK`, and to layer `PERCENT_RANK` or `NTILE` on top.

---

## Schema DDL

```sql
CREATE TABLE products (
    product_id   INT          NOT NULL PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    category     VARCHAR(50)  NOT NULL
);

CREATE TABLE order_items (
    order_id     INT            NOT NULL,
    product_id   INT            NOT NULL,
    quantity     INT            NOT NULL,
    unit_price   DECIMAL(10,2)  NOT NULL
);

-- Products (10 products across 3 categories)
INSERT INTO products (product_id, product_name, category) VALUES
(1,  'Wireless Mouse',      'Electronics'),
(2,  'Mechanical Keyboard', 'Electronics'),
(3,  'USB-C Hub',           'Electronics'),
(4,  'Monitor Stand',       'Electronics'),
(5,  'Yoga Mat',            'Sports'),
(6,  'Resistance Bands',    'Sports'),
(7,  'Jump Rope',           'Sports'),
(8,  'Foam Roller',         'Sports'),
(9,  'Python Cookbook',      'Books'),
(10, 'SQL Pocket Guide',    'Books');

-- Order items (15 rows with deliberate ties in revenue)
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(1001, 1,  5, 29.99),
(1002, 2,  3, 89.99),
(1003, 3,  10, 24.99),
(1004, 4,  10, 24.99),
(1005, 1,  2, 29.99),
(1006, 5,  8, 34.99),
(1007, 6,  6, 19.99),
(1008, 7,  4, 14.99),
(1009, 8,  3, 24.99),
(1010, 5,  4, 34.99),
(1011, 9,  7, 45.99),
(1012, 10, 12, 19.99),
(1013, 6,  10, 19.99),
(1014, 9,  5, 45.99),
(1015, 10, 5, 19.99);
```

---

## Sample Input

**products**

| product_id | product_name       | category    |
|------------|--------------------|-------------|
| 1          | Wireless Mouse     | Electronics |
| 2          | Mechanical Keyboard| Electronics |
| 3          | USB-C Hub          | Electronics |
| 4          | Monitor Stand      | Electronics |
| 5          | Yoga Mat           | Sports      |
| 6          | Resistance Bands   | Sports      |
| 7          | Jump Rope          | Sports      |
| 8          | Foam Roller        | Sports      |
| 9          | Python Cookbook     | Books       |
| 10         | SQL Pocket Guide   | Books       |

**order_items**

| order_id | product_id | quantity | unit_price |
|----------|-----------|----------|------------|
| 1001     | 1         | 5        | 29.99      |
| 1002     | 2         | 3        | 89.99      |
| 1003     | 3         | 10       | 24.99      |
| 1004     | 4         | 10       | 24.99      |
| 1005     | 1         | 2        | 29.99      |
| 1006     | 5         | 8        | 34.99      |
| 1007     | 6         | 6        | 19.99      |
| 1008     | 7         | 4        | 14.99      |
| 1009     | 8         | 3        | 24.99      |
| 1010     | 5         | 4        | 34.99      |
| 1011     | 9         | 7        | 45.99      |
| 1012     | 10        | 12       | 19.99      |
| 1013     | 6         | 10       | 19.99      |
| 1014     | 9         | 5        | 45.99      |
| 1015     | 10        | 5        | 19.99      |

---

## Expected Output

**Top 3 per Category (with ties) + Percentiles**

| category    | product_name        | total_revenue | dense_rnk | pct_rank |
|-------------|---------------------|---------------|-----------|----------|
| Books       | Python Cookbook     | 551.88        | 1         | 1.00     |
| Books       | SQL Pocket Guide    | 339.83        | 2         | 0.00     |
| Electronics | Mechanical Keyboard | 269.97        | 1         | 1.00     |
| Electronics | Monitor Stand       | 249.90        | 2         | 0.33     |
| Electronics | USB-C Hub           | 249.90        | 2         | 0.33     |
| Electronics | Wireless Mouse      | 209.93        | 3         | 0.00     |
| Sports      | Yoga Mat            | 419.88        | 1         | 1.00     |
| Sports      | Resistance Bands    | 319.84        | 2         | 0.67     |
| Sports      | Foam Roller         | 74.97         | 3         | 0.33     |

> **Note:** `Monitor Stand` and `USB-C Hub` tie at $249.90, so both receive `dense_rnk = 2` and both appear in the output (giving 4 rows for Electronics). In Sports, `Jump Rope` ($59.96, `dense_rnk = 4`) is excluded by the `dense_rnk <= 3` Top 3 filter, while `Foam Roller` ($74.97, `dense_rnk = 3`) is included.

*The exact percentile values follow `PERCENT_RANK() OVER (PARTITION BY category ORDER BY total_revenue ASC) = (rank_asc - 1) / (count - 1)` within each category (so the top-earning product is `1.00`, and tied items at rank 2 of 4 from the bottom share `(2 - 1) / (4 - 1) = 0.33`).*

---

## Brute Force Solution

```sql
-- Step 1: Compute total revenue per product
-- Step 2: Join to products for category
-- Step 3: Use a correlated subquery to compute rank

WITH product_revenue AS (
    SELECT
        oi.product_id,
        SUM(oi.quantity * oi.unit_price) AS total_revenue
    FROM order_items oi
    GROUP BY oi.product_id
),

ranked AS (
    SELECT
        p.category,
        p.product_name,
        pr.total_revenue,
        -- Correlated subquery to count distinct higher revenues = dense rank
        (
            SELECT COUNT(DISTINCT pr2.total_revenue)
            FROM product_revenue pr2
            JOIN products p2 ON pr2.product_id = p2.product_id
            WHERE p2.category = p.category
              AND pr2.total_revenue > pr.total_revenue
        ) + 1 AS dense_rnk
    FROM product_revenue pr
    JOIN products p ON pr.product_id = p.product_id
)

SELECT
    category,
    product_name,
    ROUND(total_revenue, 2) AS total_revenue,
    dense_rnk,
    -- Compute percentile rank manually (ascending revenue: 0.00 = lowest, 1.00 = highest)
    CASE
        WHEN (SELECT COUNT(*) FROM ranked r2 WHERE r2.category = ranked.category) = 1
        THEN 0.00
        ELSE ROUND(
            (SELECT COUNT(*) * 1.0 FROM ranked r2
             WHERE r2.category = ranked.category
               AND r2.total_revenue < ranked.total_revenue)
            / (SELECT COUNT(*) - 1 FROM ranked r2 WHERE r2.category = ranked.category),
            2
        )
    END AS pct_rank
FROM ranked
WHERE dense_rnk <= 3
ORDER BY category, dense_rnk, product_name;
```

### Explanation

1. **product_revenue** — Aggregates order items to compute total revenue per product.
2. **ranked** — A correlated subquery counts how many distinct revenue values in the same category are strictly greater than the current product's revenue, then adds 1. This replicates `DENSE_RANK` logic manually.
3. **Percentile** — Computed manually using the formula `(rank - 1) / (count - 1)`.

**Drawback:** The correlated subquery runs once per row, resulting in O(n²) complexity per category. The manual percentile calculation is also error-prone and verbose.

---

## Optimal Solution

```sql
WITH product_revenue AS (
    SELECT
        p.category,
        p.product_name,
        SUM(oi.quantity * oi.unit_price) AS total_revenue
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY p.category, p.product_name
),

ranked AS (
    SELECT
        category,
        product_name,
        total_revenue,
        DENSE_RANK() OVER (
            PARTITION BY category
            ORDER BY total_revenue DESC
        ) AS dense_rnk,
        PERCENT_RANK() OVER (
            PARTITION BY category
            ORDER BY total_revenue ASC
        ) AS pct_rank
    FROM product_revenue
)

SELECT
    category,
    product_name,
    total_revenue,
    dense_rnk,
    ROUND(CAST(pct_rank AS NUMERIC), 2) AS pct_rank
FROM ranked
WHERE dense_rnk <= 3
ORDER BY category, dense_rnk, product_name;
```

### Why This Is Better

| Aspect | Brute Force | Optimal |
|--------|------------|---------|
| **Complexity** | O(n²) per category (correlated subquery) | O(n log n) per category (single sort for window functions) |
| **Readability** | 30+ lines with nested subqueries | Clean, declarative window functions |
| **Tie handling** | Manual counting of distinct values | Built-in via `DENSE_RANK` — semantically correct by definition |
| **Percentile** | Hand-rolled formula with edge-case guards | Standard `PERCENT_RANK()` — portable and tested |
| **Maintainability** | Changing to "Top 5" requires understanding the subquery | Change `<= 3` to `<= 5` — one number |

**Key design choice — `DENSE_RANK` vs `RANK` vs `ROW_NUMBER`:**

| Function | Tie Behavior | Example Ranks for Revenues 100, 90, 90, 80 |
|----------|-------------|---------------------------------------------|
| `ROW_NUMBER` | No ties — arbitrary tiebreak | 1, 2, 3, 4 |
| `RANK` | Ties share rank, next rank skipped | 1, 2, 2, 4 |
| `DENSE_RANK` | Ties share rank, no gap | 1, 2, 2, 3 |

For "Top N with ties" problems, `DENSE_RANK` is almost always the correct choice because it guarantees exactly N distinct rank levels while including all tied items.

---

## Interviewer Follow-Up Questions

1. **"What if we need exactly 3 rows per category, no more, even with ties?"**
   Switch from `DENSE_RANK` to `ROW_NUMBER`. Since `ROW_NUMBER` assigns unique sequential integers, filtering `WHERE rn <= 3` always returns at most 3 rows per partition. However, the tiebreaking is non-deterministic unless you add a secondary `ORDER BY` column (e.g., `product_name`). Always mention this trade-off.

2. **"How would you compute NTILE(4) quartiles and show which quartile each product falls into?"**
   Add `NTILE(4) OVER (PARTITION BY category ORDER BY total_revenue DESC) AS quartile` to the ranked CTE. `NTILE` divides rows into approximately equal-sized buckets, which is useful for grouping products into "Top 25%", "25-50%", etc. Note that `NTILE` does not handle ties — products with the same revenue can end up in different quartiles.

3. **"The product catalog has 10 million rows. How do you optimize?"**
   - Pre-aggregate `order_items` into a materialized summary table (`product_id`, `total_revenue`).
   - Index `order_items` on `(product_id)` and `products` on `(category, product_id)`.
   - If only top N is needed, some engines support `QUALIFY` to fuse the filter with the window function, avoiding a subquery/CTE layer.

---

## Key Takeaways

- **Know when to use each ranking function**: `ROW_NUMBER` for unique row selection, `RANK` for competition-style ranking (with gaps), `DENSE_RANK` for top-N with ties (no gaps).
- **`DENSE_RANK` is the default choice** for "Top N per group" interview problems because it preserves ties without skipping ranks.
- **`PERCENT_RANK`** follows the formula `(rank - 1) / (partition_size - 1)` and ranges from 0 to 1. It is the standard way to compute relative standing.
- **`PARTITION BY`** in window functions acts as a per-group scope — analogous to `GROUP BY` but without collapsing rows.
- **Filtering on window functions** requires a subquery or CTE because `WHERE` is evaluated before window functions in SQL's logical order of operations. Some dialects support `QUALIFY` as a shortcut.
- Always confirm with the interviewer: **Does "Top 3" mean exactly 3 rows or up to 3 rank levels?** This determines your function choice.
