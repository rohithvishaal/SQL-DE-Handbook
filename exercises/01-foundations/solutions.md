# Module 1 Solutions: SQL Foundations & Core Operations

---

## Part A: Multiple Choice

### Question 1 — Logical Query Execution & Filtering
**Correct Answer:** **C**

**Explanation:**
- **C is correct** because `HAVING` runs after `GROUP BY` and filters grouped aggregates using the full aggregate expression `AVG(row_count) > 10000`.
- **A is wrong** because `WHERE` runs *before* `GROUP BY` and cannot reference aggregate functions like `AVG()`.
- **B is wrong** in strict ANSI SQL because `SELECT` aliases (`avg_rows`) are evaluated *after* `HAVING` and cannot be referenced inside `HAVING` (even though some engines like MySQL/BigQuery allow it as a non-portable extension).
- **D is wrong** because `ORDER BY` sorts rows; `avg_rows > 10000` is a boolean expression, not a filter.

---

### Question 2 — The `LEFT JOIN` Filter Trap
**Correct Answer:** **C** (1 row: `101 -> US`)

**Explanation:**
After the `LEFT JOIN`, the intermediate rows are:
- `(order_id=1, customer_id=101, country='US')`
- `(order_id=2, customer_id=102, country='CA')`
- `(order_id=3, customer_id=999, country=NULL)`

Next, the `WHERE c.country = 'US'` clause evaluates:
- `'US' = 'US'` → `TRUE` (kept)
- `'CA' = 'US'` → `FALSE` (dropped)
- `NULL = 'US'` → `UNKNOWN` (dropped)

Putting a right-table filter in `WHERE` silently converts the `LEFT JOIN` into an `INNER JOIN`. To preserve unmatched orders, move the filter into the `ON` clause (`AND c.country = 'US'`).

---

### Question 3 — Three-Valued Logic & `NOT IN`
**Correct Answer:** **D** (0 rows)

**Explanation:**
`user_id NOT IN (2, NULL)` is logically rewritten by SQL as:
`user_id <> 2 AND user_id <> NULL`

For `user_id = 1`: `1 <> 2` (`TRUE`) `AND` `1 <> NULL` (`UNKNOWN`) → `UNKNOWN`.  
For `user_id = 3`: `3 <> 2` (`TRUE`) `AND` `3 <> NULL` (`UNKNOWN`) → `UNKNOWN`.

Because `WHERE` only keeps rows evaluating to `TRUE`, **zero rows** are returned. Always use `NOT EXISTS` instead of `NOT IN` when the subquery column can contain `NULL`.

---

### Question 4 — Set Operations (`UNION` vs `UNION ALL` & `INTERSECT`)
**Correct Answer:** **B**

**Explanation:**
- **B is correct:** `UNION ALL` simply concatenates both result sets without deduplicating, and requires identical column counts with compatible types.
- **A is wrong:** `UNION` is *slower* than `UNION ALL` because it must perform an extra sort or hash aggregation to remove duplicates.
- **C is wrong:** Unlike `=` in `WHERE`/`JOIN`, set operations (`UNION`, `INTERSECT`, `EXCEPT`) treat two `NULL` values as equal/identical for set matching.
- **D is wrong:** `EXCEPT` returns rows in the first query that are *not* in the second (set difference `A - B`), not the symmetric difference.

---

### Question 5 — `NULLIF` & Sentinel Values
**Correct Answer:** **C** (`NULL`)

**Explanation:**
`NULLIF(impressions, 0)` compares `impressions` to `0`. Because `0 = 0`, `NULLIF` returns `NULL`. Dividing any number by `NULL` (`10 / NULL`) evaluates to `NULL` instead of crashing the pipeline with a division-by-zero error.

---

## Part B: Write the Query

### Question 6 — Orphan Record Detection (Anti-Join)

**Solution (Recommended — `NOT EXISTS`):**
```sql
SELECT
    f.shipment_id,
    f.warehouse_id
FROM fact_shipments AS f
WHERE NOT EXISTS (
    SELECT 1
    FROM dim_warehouses AS w
    WHERE w.warehouse_id = f.warehouse_id
);
```

**Alternative (`LEFT JOIN` + `IS NULL`):**
```sql
SELECT
    f.shipment_id,
    f.warehouse_id
FROM fact_shipments AS f
LEFT JOIN dim_warehouses AS w
    ON f.warehouse_id = w.warehouse_id
WHERE w.warehouse_id IS NULL;
```

**Expected Output:**

| shipment_id | warehouse_id |
|-------------|--------------|
| S101        | W9           |
| S102        | NULL         |

**Explanation:**
- Using `NOT IN (SELECT warehouse_id FROM dim_warehouses)` would fail catastrophically here and return **0 rows** because `dim_warehouses` contains a `NULL` `warehouse_id`.
- With `NOT EXISTS`, for `S102` (`f.warehouse_id IS NULL`), `w.warehouse_id = NULL` evaluates to `UNKNOWN` for every row in `dim_warehouses` (even the `NULL` row), so `EXISTS` is `FALSE` and `NOT EXISTS` is `TRUE` — correctly flagging `S102` as an orphan.
- With `LEFT JOIN`, `S102` does not match any row in `dim_warehouses`, so `w.warehouse_id` is `NULL` in the joined result and is retained.

---

### Question 7 — Fan-Out Diagnosis & Prevention

**1. Diagnostic Query:**
```sql
SELECT
    currency,
    rate_date,
    COUNT(*) AS rate_row_count
FROM dim_exchange_rates
GROUP BY currency, rate_date
HAVING COUNT(*) > 1;
```

*Expected output (diagnosis):*

| currency | rate_date  | rate_row_count |
|----------|------------|----------------|
| EUR      | 2024-03-01 | 2              |

**2. Fixed Revenue Query (Pre-aggregate right table to match join grain):**
```sql
WITH daily_rates AS (
    SELECT
        currency,
        rate_date,
        AVG(usd_rate) AS avg_usd_rate
    FROM dim_exchange_rates
    GROUP BY currency, rate_date
)
SELECT
    SUM(o.amount * r.avg_usd_rate) AS total_usd_revenue
FROM fact_orders AS o
INNER JOIN daily_rates AS r
    ON o.currency = r.currency
   AND o.order_date = r.rate_date;
```

*Expected output (fixed revenue):*

| total_usd_revenue |
|-------------------|
| 362.50            |

*(Calculation: `100.00 * ((1.08 + 1.09) / 2) + 200.00 * 1.27 = 100.00 * 1.085 + 254.00 = 108.50 + 254.00 = 362.50`.)*

**Explanation:**
Joining directly on `(currency, rate_date)` without deduplicating `dim_exchange_rates` duplicates the `EUR` order row (`100 * 1.08 + 100 * 1.09 + 254 = 471.00`), inflating revenue by `$108.50`. Pre-aggregating `dim_exchange_rates` to the `(currency, rate_date)` grain guarantees a strict many-to-one join.

---

### Question 8 — Two-Source Snapshot Reconciliation (`FULL OUTER JOIN` + `IS DISTINCT FROM`)

**Solution:**
```sql
SELECT
    COALESCE(y.user_id, t.user_id) AS user_id,
    y.status AS prev_status,
    t.status AS curr_status,
    CASE
        WHEN y.user_id IS NULL THEN 'added'
        WHEN t.user_id IS NULL THEN 'deleted'
        WHEN y.status IS DISTINCT FROM t.status THEN 'updated'
        ELSE 'unchanged'
    END AS change_type
FROM snap_yesterday AS y
FULL OUTER JOIN snap_today AS t
    ON y.user_id = t.user_id
ORDER BY user_id;
```

**Expected Output:**

| user_id | prev_status | curr_status | change_type |
|---------|-------------|-------------|-------------|
| 1       | active      | active      | unchanged   |
| 2       | pending     | suspended   | updated     |
| 3       | NULL        | NULL        | unchanged   |
| 4       | active      | NULL        | deleted     |
| 5       | NULL        | active      | added       |

**Explanation:**
- `COALESCE(y.user_id, t.user_id)` unifies the key column from both sides of the `FULL OUTER JOIN`.
- `y.status IS DISTINCT FROM t.status` is crucial for `user_id = 3` (`NULL` vs `NULL`): standard `y.status <> t.status` would evaluate to `UNKNOWN`, and `y.status = t.status` would also evaluate to `UNKNOWN`, making NULL-preserving equality error-prone without `IS DISTINCT FROM`.
- *(Note: If targeting an engine without `IS DISTINCT FROM`, use `(y.status <> t.status OR (y.status IS NULL AND t.status IS NOT NULL) OR (y.status IS NOT NULL AND t.status IS NULL))`.)*

---

### Question 9 — Safe Type Casting & Dirty Data Cleaning

**Solution (using `TRY_CAST`):**
```sql
SELECT
    payment_id,
    TRY_CAST(NULLIF(TRIM(amount_raw), '') AS DECIMAL(10, 2)) AS amount_clean,
    COALESCE(NULLIF(TRIM(currency_raw), ''), 'UNKNOWN')      AS currency_clean,
    CASE
        WHEN NULLIF(TRIM(amount_raw), '') IS NOT NULL
         AND TRY_CAST(NULLIF(TRIM(amount_raw), '') AS DECIMAL(10, 2)) IS NULL
        THEN TRUE
        ELSE FALSE
    END AS is_amount_parse_error
FROM raw_payments
ORDER BY payment_id;
```

**ANSI-Portable Alternative (without `TRY_CAST`, e.g., PostgreSQL):**
If your dialect lacks `TRY_CAST` / `SAFE_CAST`, validate the pattern with a `CASE` guard before `CAST`:
```sql
-- Example regex guard for positive decimals in PostgreSQL:
CASE
    WHEN TRIM(amount_raw) ~ '^\d+(\.\d{1,2})?$'
    THEN CAST(TRIM(amount_raw) AS DECIMAL(10, 2))
    ELSE NULL
END
```

**Expected Output:**

| payment_id | amount_clean | currency_clean | is_amount_parse_error |
|------------|--------------|----------------|-----------------------|
| P1         | 150.25       | USD            | FALSE                 |
| P2         | NULL         | EUR            | TRUE                  |
| P3         | 75.00        | UNKNOWN        | FALSE                 |
| P4         | NULL         | UNKNOWN        | TRUE                  |
| P5         | 200.50       | GBP            | FALSE                 |

**Explanation:**
- `NULLIF(TRIM(currency_raw), '')` turns whitespace or empty strings into proper `NULL`s so `COALESCE(..., 'UNKNOWN')` handles both missing and blank values uniformly.
- Wrapping `TRY_CAST` with an error-flag column lets downstream data-quality monitors count or quarantine malformed inputs (`P2`, `P4`) instead of silently dropping bad records.

---

### Question 10 — Semi-Join & Post-Aggregation Filtering

**Solution:**
```sql
SELECT
    a.account_id,
    a.account_name
FROM dim_accounts AS a
INNER JOIN pipeline_runs AS r
    ON a.account_id = r.account_id
WHERE a.tier = 'enterprise'
GROUP BY a.account_id, a.account_name
HAVING AVG(r.duration_sec) > 200
   AND SUM(CASE WHEN r.status = 'failed' THEN 1 ELSE 0 END) >= 1;
```

**Alternative (explicit `EXISTS` semi-join + `GROUP BY` / `HAVING`):**
```sql
SELECT
    a.account_id,
    a.account_name
FROM dim_accounts AS a
WHERE a.tier = 'enterprise'
  AND EXISTS (
      SELECT 1
      FROM pipeline_runs AS r
      WHERE r.account_id = a.account_id
        AND r.status = 'failed'
  )
  AND (
      SELECT AVG(r2.duration_sec)
      FROM pipeline_runs AS r2
      WHERE r2.account_id = a.account_id
  ) > 200;
```

**Expected Output:**

| account_id | account_name |
|------------|--------------|
| A1         | Acme Corp    |

**Explanation:**
Let's trace each account:
- `A1` (`Acme Corp`): `'enterprise'`, has failed runs (`run_id` 1 & 2), `AVG(duration_sec) = (300 + 250) / 2 = 275 > 200` → **Included** (1 row, no duplicate despite 2 failed runs).
- `A2` (`Beta Labs`): `tier = 'starter'` → **Excluded**.
- `A3` (`Globex Inc`): `'enterprise'`, `AVG = 400 > 200`, but 0 `'failed'` runs → **Excluded**.
- `A4` (`Initech`): `'enterprise'`, has 1 `'failed'` run, but `AVG = (100 + 150) / 2 = 125 <= 200` → **Excluded**.
