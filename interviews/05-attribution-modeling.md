# First-Touch vs Last-Touch vs Linear Marketing Attribution

> Multi-Touch Attribution Modeling in SQL

**Difficulty:** Hard

**Companies:** Google, Meta, Pinterest, Snap

---

## Problem Statement

You are a marketing data analyst at a direct-to-consumer (DTC) e-commerce brand. The marketing team runs campaigns across multiple channels — organic search, paid social, email, and display ads. They need to understand which channels actually drive conversions (purchases). The challenge: a customer typically interacts with several channels before buying. The team wants three attribution models computed side-by-side: **First-Touch** (100% credit to the first interaction), **Last-Touch** (100% credit to the last interaction before purchase), and **Linear** (credit split equally across all touchpoints). Given a table of marketing touchpoints and a table of conversions, compute the attributed revenue for each channel under all three models. This is one of the most realistic and commonly asked data engineering interview problems at ad-tech and growth-focused companies.

---

## Schema DDL

```sql
CREATE TABLE touchpoints (
    touchpoint_id  INT           NOT NULL PRIMARY KEY,
    user_id        INT           NOT NULL,
    channel        VARCHAR(50)   NOT NULL,  -- e.g. 'organic_search', 'paid_social', 'email', 'display'
    touchpoint_ts  TIMESTAMP     NOT NULL
);

CREATE TABLE conversions (
    conversion_id   INT            NOT NULL PRIMARY KEY,
    user_id         INT            NOT NULL,
    conversion_ts   TIMESTAMP      NOT NULL,
    revenue         DECIMAL(10,2)  NOT NULL
);

-- Touchpoints (15 rows, 4 users across 4 channels)
INSERT INTO touchpoints (touchpoint_id, user_id, channel, touchpoint_ts) VALUES
(1,  100, 'organic_search', '2024-04-01 09:00:00'),
(2,  100, 'paid_social',    '2024-04-03 14:30:00'),
(3,  100, 'email',          '2024-04-05 10:00:00'),
(4,  200, 'display',        '2024-04-02 11:00:00'),
(5,  200, 'paid_social',    '2024-04-04 16:00:00'),
(6,  200, 'email',          '2024-04-06 09:00:00'),
(7,  200, 'organic_search', '2024-04-07 08:00:00'),
(8,  300, 'paid_social',    '2024-04-01 12:00:00'),
(9,  300, 'display',        '2024-04-02 15:00:00'),
(10, 300, 'organic_search', '2024-04-03 10:00:00'),
(11, 300, 'email',          '2024-04-05 11:00:00'),
(12, 300, 'paid_social',    '2024-04-06 13:00:00'),
(13, 400, 'email',          '2024-04-01 10:00:00'),
(14, 400, 'display',        '2024-04-03 14:00:00'),
(15, 400, 'paid_social',    '2024-04-04 09:00:00');

-- Conversions (4 rows — one per user)
INSERT INTO conversions (conversion_id, user_id, conversion_ts, revenue) VALUES
(1001, 100, '2024-04-06 18:00:00', 120.00),
(1002, 200, '2024-04-08 12:00:00', 250.00),
(1003, 300, '2024-04-07 10:00:00', 80.00),
(1004, 400, '2024-04-05 16:00:00', 200.00);
```

---

## Sample Input

**touchpoints**

| touchpoint_id | user_id | channel        | touchpoint_ts       |
|---------------|---------|----------------|---------------------|
| 1             | 100     | organic_search | 2024-04-01 09:00:00 |
| 2             | 100     | paid_social    | 2024-04-03 14:30:00 |
| 3             | 100     | email          | 2024-04-05 10:00:00 |
| 4             | 200     | display        | 2024-04-02 11:00:00 |
| 5             | 200     | paid_social    | 2024-04-04 16:00:00 |
| 6             | 200     | email          | 2024-04-06 09:00:00 |
| 7             | 200     | organic_search | 2024-04-07 08:00:00 |
| 8             | 300     | paid_social    | 2024-04-01 12:00:00 |
| 9             | 300     | display        | 2024-04-02 15:00:00 |
| 10            | 300     | organic_search | 2024-04-03 10:00:00 |
| 11            | 300     | email          | 2024-04-05 11:00:00 |
| 12            | 300     | paid_social    | 2024-04-06 13:00:00 |
| 13            | 400     | email          | 2024-04-01 10:00:00 |
| 14            | 400     | display        | 2024-04-03 14:00:00 |
| 15            | 400     | paid_social    | 2024-04-04 09:00:00 |

**conversions**

| conversion_id | user_id | conversion_ts       | revenue |
|---------------|---------|---------------------|---------|
| 1001          | 100     | 2024-04-06 18:00:00 | 120.00  |
| 1002          | 200     | 2024-04-08 12:00:00 | 250.00  |
| 1003          | 300     | 2024-04-07 10:00:00 | 80.00   |
| 1004          | 400     | 2024-04-05 16:00:00 | 200.00  |

---

## Expected Output

**Per-Channel Attributed Revenue (All Three Models)**

| channel        | first_touch_revenue | last_touch_revenue | linear_revenue |
|----------------|---------------------|--------------------|----------------|
| display        | 250.00              | 0.00               | 145.17         |
| email          | 200.00              | 120.00             | 185.17         |
| organic_search | 120.00              | 250.00             | 118.50         |
| paid_social    | 80.00               | 280.00             | 201.17         |

> **Derivation sketch (linear model):**
> - User 100 (revenue $120, 3 touchpoints): `organic_search` $40, `paid_social` $40, `email` $40 (first: `organic_search`, last: `email`)
> - User 200 (revenue $250, 4 touchpoints): `display` $62.50, `paid_social` $62.50, `email` $62.50, `organic_search` $62.50 (first: `display`, last: `organic_search`)
> - User 300 (revenue $80, 5 touchpoints): `paid_social` $16×2=$32, `display` $16, `organic_search` $16, `email` $16 (first: `paid_social`, last: `paid_social`)
> - User 400 (revenue $200, 3 touchpoints): `email` $66.67, `display` $66.67, `paid_social` $66.67 (first: `email`, last: `paid_social`)

---

## Brute Force Solution

```sql
-- Step 1: Associate touchpoints with conversions
-- Step 2: Use correlated subqueries to identify first and last touch per user
-- Step 3: Aggregate across three separate passes

-- First-Touch attribution
WITH pre_conversion_touchpoints AS (
    -- Only touchpoints that occurred before the conversion
    SELECT
        t.touchpoint_id,
        t.user_id,
        t.channel,
        t.touchpoint_ts,
        c.conversion_id,
        c.revenue
    FROM touchpoints t
    JOIN conversions c
        ON  t.user_id = c.user_id
        AND t.touchpoint_ts < c.conversion_ts
),

first_touch AS (
    SELECT pct.*
    FROM pre_conversion_touchpoints pct
    WHERE pct.touchpoint_ts = (
        SELECT MIN(pct2.touchpoint_ts)
        FROM pre_conversion_touchpoints pct2
        WHERE pct2.user_id = pct.user_id
          AND pct2.conversion_id = pct.conversion_id
    )
),

last_touch AS (
    SELECT pct.*
    FROM pre_conversion_touchpoints pct
    WHERE pct.touchpoint_ts = (
        SELECT MAX(pct2.touchpoint_ts)
        FROM pre_conversion_touchpoints pct2
        WHERE pct2.user_id = pct.user_id
          AND pct2.conversion_id = pct.conversion_id
    )
),

linear_touch AS (
    SELECT
        pct.channel,
        pct.conversion_id,
        (pct.revenue * 1.0) / (
            SELECT COUNT(*)
            FROM pre_conversion_touchpoints pct2
            WHERE pct2.user_id = pct.user_id
              AND pct2.conversion_id = pct.conversion_id
        ) AS attributed_revenue
    FROM pre_conversion_touchpoints pct
),

ft_agg AS (
    SELECT channel, SUM(revenue) AS first_touch_revenue
    FROM first_touch
    GROUP BY channel
),

lt_agg AS (
    SELECT channel, SUM(revenue) AS last_touch_revenue
    FROM last_touch
    GROUP BY channel
),

lin_agg AS (
    SELECT channel, SUM(attributed_revenue) AS linear_revenue
    FROM linear_touch
    GROUP BY channel
)

SELECT
    COALESCE(ft.channel, lt.channel, lin.channel)         AS channel,
    COALESCE(ft.first_touch_revenue, 0)                   AS first_touch_revenue,
    COALESCE(lt.last_touch_revenue, 0)                    AS last_touch_revenue,
    ROUND(COALESCE(lin.linear_revenue, 0), 2)             AS linear_revenue
FROM ft_agg ft
FULL OUTER JOIN lt_agg lt   ON ft.channel = lt.channel
FULL OUTER JOIN lin_agg lin ON COALESCE(ft.channel, lt.channel) = lin.channel
ORDER BY channel;
```

### Explanation

1. **pre_conversion_touchpoints** — Joins touchpoints to conversions, keeping only touchpoints that occurred before the conversion timestamp.
2. **first_touch / last_touch** — Uses correlated subqueries to find the MIN/MAX timestamp per user-conversion pair, then filters to those rows.
3. **linear_touch** — Divides each conversion's revenue equally among all its touchpoints via a correlated COUNT subquery.
4. **Three separate aggregations** are joined together with FULL OUTER JOINs to produce the final report.

**Drawback:** Three separate correlated subqueries, three separate aggregations, and a triple FULL OUTER JOIN. This is O(n²) per conversion path and extremely hard to extend to new models.

---

## Optimal Solution

```sql
WITH pre_conversion AS (
    -- Step 1: Join touchpoints to conversions, keeping only pre-conversion touches
    SELECT
        t.user_id,
        t.channel,
        t.touchpoint_ts,
        c.conversion_id,
        c.revenue,
        -- Step 2: Rank touchpoints for first/last touch
        ROW_NUMBER() OVER (
            PARTITION BY c.conversion_id
            ORDER BY t.touchpoint_ts ASC
        ) AS touch_asc,
        ROW_NUMBER() OVER (
            PARTITION BY c.conversion_id
            ORDER BY t.touchpoint_ts DESC
        ) AS touch_desc,
        -- Step 3: Count total touchpoints for linear attribution
        COUNT(*) OVER (
            PARTITION BY c.conversion_id
        ) AS total_touches
    FROM touchpoints t
    JOIN conversions c
        ON  t.user_id = c.user_id
        AND t.touchpoint_ts < c.conversion_ts
)

SELECT
    channel,
    -- First-Touch: full revenue goes to the first touchpoint (touch_asc = 1)
    SUM(CASE WHEN touch_asc  = 1 THEN revenue ELSE 0 END) AS first_touch_revenue,
    -- Last-Touch: full revenue goes to the last touchpoint (touch_desc = 1)
    SUM(CASE WHEN touch_desc = 1 THEN revenue ELSE 0 END) AS last_touch_revenue,
    -- Linear: revenue divided equally across all touchpoints
    ROUND(SUM(revenue * 1.0 / total_touches), 2)          AS linear_revenue
FROM pre_conversion
GROUP BY channel
ORDER BY channel;
```

### Why This Is Better

| Aspect | Brute Force | Optimal |
|--------|------------|---------|
| **CTEs / passes** | 7 CTEs + FULL OUTER JOINs | 1 CTE + 1 aggregation |
| **Correlated subqueries** | 3 separate correlated subqueries (O(n²)) | 0 — all logic in window functions (O(n log n)) |
| **Extensibility** | Adding a new model means a new CTE chain | Add one more CASE WHEN expression |
| **Readability** | 50+ lines of JOIN spaghetti | 25 lines, each model is a single expression |

**Key techniques:**
- `ROW_NUMBER() ... ORDER BY ASC` identifies the first touch (`= 1`).
- `ROW_NUMBER() ... ORDER BY DESC` identifies the last touch (`= 1`).
- `COUNT(*) OVER (PARTITION BY conversion_id)` gives the denominator for linear attribution — no subquery needed.
- All three models are computed in a **single GROUP BY** pass, which is both faster and far easier to audit.

> [!TIP]
> To add **Time-Decay** attribution, add a weight column: `EXP(-decay_rate * EXTRACT(EPOCH FROM (conversion_ts - touchpoint_ts)))` and divide each weight by the sum of weights per conversion using `SUM(weight) OVER (PARTITION BY conversion_id)`.

---

## Interviewer Follow-Up Questions

1. **"How would you implement a time-decay attribution model?"**
   Assign each touchpoint a weight inversely proportional to the time gap between the touchpoint and the conversion. A common formula is exponential decay: `weight = EXP(-λ * hours_before_conversion)`. Normalize weights per conversion by dividing each by `SUM(weight) OVER (PARTITION BY conversion_id)`, then multiply by revenue.

   ```sql
   -- Inside the pre_conversion CTE, add:
   EXP(-0.01 * EXTRACT(EPOCH FROM (c.conversion_ts - t.touchpoint_ts)) / 3600.0) AS decay_weight
   -- Then normalize:
   decay_weight / SUM(decay_weight) OVER (PARTITION BY c.conversion_id) AS normalized_weight
   -- Attribution: SUM(revenue * normalized_weight)
   ```

2. **"A user may convert multiple times. How do you handle that?"**
   Use a **lookback window**: for each conversion, only consider touchpoints within the last N days (e.g., 30 days). Add `AND t.touchpoint_ts >= c.conversion_ts - INTERVAL '30' DAY` to the join. Also, assign each touchpoint to the *nearest subsequent* conversion to avoid double-counting. This can be done with `LEAD(conversion_ts)` to define attribution windows.

3. **"How would you validate the attribution results?"**
   - **Conservation check**: Total first_touch_revenue = total last_touch_revenue = total linear_revenue = total actual revenue. All three models must sum to the same grand total.
   - **Per-conversion check**: For each conversion, sum of attributed revenue across all touchpoints should equal the conversion's revenue exactly.
   - **Edge cases**: Users with a single touchpoint should show identical values across all three models. Users with no pre-conversion touchpoints should be flagged as "direct/unattributed."

---

## Key Takeaways

- **Attribution modeling** is fundamentally about distributing a conversion's value across the touchpoints that preceded it. The choice of model is a business decision, not a technical one.
- **ROW_NUMBER with ASC/DESC ordering** is the cleanest way to identify first and last events in a sequence — no need for correlated subqueries or self-joins.
- **`COUNT(*) OVER (PARTITION BY ...)`** provides per-group denominators without an extra aggregation step — essential for linear attribution.
- **All models should sum to the same total revenue.** This is the primary validation check and a great thing to mention proactively in an interview.
- **Window functions turn N separate queries into one pass.** Whenever you find yourself writing multiple aggregation CTEs over the same base data, ask: can window functions combine them?
- **Real-world extensions** include time-decay, position-based (U-shaped: 40% first, 40% last, 20% middle), and data-driven (Shapley value or Markov chain) models. Mentioning these shows depth.
- Always **clarify the lookback window** and what counts as a "touchpoint" — does a page view count? Only paid clicks? This scoping question is critical in real attribution work.
