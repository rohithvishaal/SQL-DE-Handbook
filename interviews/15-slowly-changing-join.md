# Point-in-Time / Temporal Joins for SCD Type 2 Lookups

## Difficulty

🔴 **Hard**

## Companies

Netflix, Airbnb, Stripe, Spotify, DoorDash, Robinhood

---

## Problem Statement

You are a Data Engineer at a FinTech / SaaS billing platform. Customer subscription tiers, fee rates, and account statuses are tracked in a **Slowly Changing Dimension Type 2 (SCD Type 2)** table (`dim_merchant_scd2`), where each version of a merchant's profile has `[valid_from, valid_to)` validity boundaries and an `is_current` flag.

Meanwhile, a high-volume fact table (`fact_transactions`) records payment events with a `txn_timestamp`. To audit historical fee revenue accurately, Finance requires a **Point-in-Time (Temporal) Join**: every transaction must be enriched with the exact `fee_rate_bps` (basis points) and `tier` that the merchant had **at the exact moment `txn_timestamp` occurred** — NOT their current tier!

Additionally:
1. If a transaction happens **before** the merchant's earliest recorded SCD2 version (late-arriving or backdated event), fall back gracefully to `'UNKNOWN'` / `NULL` (or flag it as an orphan) rather than dropping the transaction!
2. If a transaction lands **exactly on a boundary timestamp** (`txn_timestamp = valid_to` of v1 = `valid_from` of v2), it must match **exclusively v2** (`valid_from <= txn_timestamp < valid_to`) — never double-count the transaction!

---

## Schema DDL

```sql
CREATE TABLE dim_merchant_scd2 (
    scd_key        INT PRIMARY KEY,
    merchant_id    INT           NOT NULL,
    tier           VARCHAR(20)   NOT NULL,
    fee_rate_bps   INT           NOT NULL, -- e.g. 290 = 2.90%
    valid_from     TIMESTAMP     NOT NULL,
    valid_to       TIMESTAMP     NOT NULL, -- '9999-12-31 23:59:59' for current row
    is_current     BOOLEAN       NOT NULL
);

CREATE TABLE fact_transactions (
    txn_id         INT PRIMARY KEY,
    merchant_id    INT            NOT NULL,
    amount         DECIMAL(12, 2) NOT NULL,
    txn_timestamp  TIMESTAMP      NOT NULL
);

INSERT INTO dim_merchant_scd2 (scd_key, merchant_id, tier, fee_rate_bps, valid_from, valid_to, is_current) VALUES
-- Merchant 1: Starter (290 bps) -> Growth (250 bps) -> Enterprise (190 bps)
(1, 1, 'Starter',    290, '2025-01-01 00:00:00', '2025-02-01 00:00:00', FALSE),
(2, 1, 'Growth',     250, '2025-02-01 00:00:00', '2025-03-15 12:00:00', FALSE),
(3, 1, 'Enterprise', 190, '2025-03-15 12:00:00', '9999-12-31 23:59:59', TRUE),

-- Merchant 2: Starter (290 bps) -> Suspended (0 bps)
(4, 2, 'Starter',    290, '2025-02-10 08:00:00', '2025-03-01 00:00:00', FALSE),
(5, 2, 'Suspended',    0, '2025-03-01 00:00:00', '9999-12-31 23:59:59', TRUE);

INSERT INTO fact_transactions (txn_id, merchant_id, amount, txn_timestamp) VALUES
(1001, 1, 1000.00, '2025-01-15 14:30:00'), -- Falls in Starter (290 bps) -> fee = 29.00
(1002, 1, 2000.00, '2025-02-01 00:00:00'), -- EXACT boundary! Must match Growth (250 bps), NOT both! -> fee = 50.00
(1003, 1, 5000.00, '2025-03-15 11:59:59'), -- 1s before Enterprise -> still Growth (250 bps) -> fee = 125.00
(1004, 1, 5000.00, '2025-03-15 12:00:00'), -- EXACT boundary -> Enterprise (190 bps) -> fee = 95.00
(1005, 2,  500.00, '2025-02-05 10:00:00'), -- Before Merchant 2's earliest SCD2 valid_from -> no match (retain row!)
(1006, 2,  800.00, '2025-02-20 09:00:00'), -- Falls in Starter (290 bps) -> fee = 23.20
(1007, 3,  300.00, '2025-03-01 10:00:00'); -- Unknown merchant not in dim_merchant_scd2 -> retain row!
```

---

## Sample Input

**dim_merchant_scd2**

| scd_key | merchant_id | tier       | fee_rate_bps | valid_from          | valid_to            | is_current |
|---------|-------------|------------|--------------|---------------------|---------------------|------------|
| 1       | 1           | Starter    | 290          | 2025-01-01 00:00:00 | 2025-02-01 00:00:00 | FALSE      |
| 2       | 1           | Growth     | 250          | 2025-02-01 00:00:00 | 2025-03-15 12:00:00 | FALSE      |
| 3       | 1           | Enterprise | 190          | 2025-03-15 12:00:00 | 9999-12-31 23:59:59 | TRUE       |
| 4       | 2           | Starter    | 290          | 2025-02-10 08:00:00 | 2025-03-01 00:00:00 | FALSE      |
| 5       | 2           | Suspended  | 0            | 2025-03-01 00:00:00 | 9999-12-31 23:59:59 | TRUE       |

**fact_transactions**

| txn_id | merchant_id | amount  | txn_timestamp       |
|--------|-------------|---------|---------------------|
| 1001   | 1           | 1000.00 | 2025-01-15 14:30:00 |
| 1002   | 1           | 2000.00 | 2025-02-01 00:00:00 |
| 1003   | 1           | 5000.00 | 2025-03-15 11:59:59 |
| 1004   | 1           | 5000.00 | 2025-03-15 12:00:00 |
| 1005   | 2           | 500.00  | 2025-02-05 10:00:00 |
| 1006   | 2           | 800.00  | 2025-02-20 09:00:00 |
| 1007   | 3           | 300.00  | 2025-03-01 10:00:00 |

---

## Expected Output

| txn_id | merchant_id | txn_timestamp       | amount  | tier       | fee_rate_bps | fee_amount |
|--------|-------------|---------------------|---------|------------|--------------|------------|
| 1001   | 1           | 2025-01-15 14:30:00 | 1000.00 | Starter    | 290          | 29.00      |
| 1002   | 1           | 2025-02-01 00:00:00 | 2000.00 | Growth     | 250          | 50.00      |
| 1003   | 1           | 2025-03-15 11:59:59 | 5000.00 | Growth     | 250          | 125.00     |
| 1004   | 1           | 2025-03-15 12:00:00 | 5000.00 | Enterprise | 190          | 95.00      |
| 1005   | 2           | 2025-02-05 10:00:00 | 500.00  | UNKNOWN    | NULL         | NULL       |
| 1006   | 2           | 2025-02-20 09:00:00 | 800.00  | Starter    | 290          | 23.20      |
| 1007   | 3           | 2025-03-01 10:00:00 | 300.00  | UNKNOWN    | NULL         | NULL       |

---

## Brute Force Solution

**Approach: Correlated scalar subquery per enriched column (or `BETWEEN` fan-out bug)**

Engineers unfamiliar with range-join semantics often either run correlated subqueries for each dimension attribute or mistakenly use `BETWEEN` (which causes duplicate rows on boundaries):

```sql
-- Correlated subquery approach (executes lookup once per row per column)
SELECT
    f.txn_id,
    f.merchant_id,
    f.txn_timestamp,
    f.amount,
    COALESCE(
        (
            SELECT d.tier
            FROM dim_merchant_scd2 d
            WHERE d.merchant_id = f.merchant_id
              AND d.valid_from <= f.txn_timestamp
            ORDER BY d.valid_from DESC
            LIMIT 1
        ),
        'UNKNOWN'
    ) AS tier,
    (
        SELECT d.fee_rate_bps
        FROM dim_merchant_scd2 d
        WHERE d.merchant_id = f.merchant_id
          AND d.valid_from <= f.txn_timestamp
        ORDER BY d.valid_from DESC
        LIMIT 1
    ) AS fee_rate_bps,
    ROUND(
        f.amount * (
            SELECT d.fee_rate_bps
            FROM dim_merchant_scd2 d
            WHERE d.merchant_id = f.merchant_id
              AND d.valid_from <= f.txn_timestamp
            ORDER BY d.valid_from DESC
            LIMIT 1
        ) / 10000.0,
        2
    ) AS fee_amount
FROM fact_transactions f
ORDER BY f.txn_id;
```

**Explanation:**
1. For every transaction row, execute 3 separate correlated subqueries looking up the latest `valid_from <= txn_timestamp`.

**Drawbacks:**
- **Catastrophic performance on large fact tables**: In engines that don't decorrelate `ORDER BY ... LIMIT 1` subqueries (or across 3 separate subqueries), this executes $3 \times N_{\text{fact}}$ index probes / nested loops — completely unscalable for billions of transactions.
- **Repeated logic** — every column you want to enrich from `dim_merchant_scd2` duplicates the exact same subquery.

> [!WARNING]
> **Classic `BETWEEN` Trap**: Writing `ON f.txn_timestamp BETWEEN d.valid_from AND d.valid_to` is **wrong** for half-open `[valid_from, valid_to)` SCD2 tables! On `txn_id = 1002` (`2025-02-01 00:00:00`), `BETWEEN` matches **both** `Starter` (`valid_to = 2025-02-01 00:00:00`) and `Growth` (`valid_from = 2025-02-01 00:00:00`), silently **doubling revenue** in your report!

---

## Optimal Solution

**Approach: Half-Open Range `LEFT JOIN` (`valid_from <= txn_timestamp < valid_to`)**

Because `dim_merchant_scd2` maintains non-overlapping half-open intervals `[valid_from, valid_to)`, a single `LEFT JOIN` with strict half-open bounds is deterministic, fan-out-free, and exposes all dimension attributes in one pass.

```sql
SELECT
    f.txn_id,
    f.merchant_id,
    f.txn_timestamp,
    f.amount,
    COALESCE(d.tier, 'UNKNOWN') AS tier,
    d.fee_rate_bps,
    ROUND(f.amount * d.fee_rate_bps / 10000.0, 2) AS fee_amount
FROM fact_transactions f
LEFT JOIN dim_merchant_scd2 d
  ON f.merchant_id   = d.merchant_id
 AND f.txn_timestamp >= d.valid_from
 AND f.txn_timestamp <  d.valid_to
ORDER BY f.txn_id;
```

### Defensive Variant (When Source SCD2 Intervals Might Overlap or Have Gaps)

If upstream ETL bugs can temporarily leave dirty overlapping `valid_from`/`valid_to` windows in `dim_merchant_scd2`, deduplicate the match with `ROW_NUMBER()` so a fact row can never fan out:

```sql
WITH matched AS (
    SELECT
        f.txn_id,
        f.merchant_id,
        f.txn_timestamp,
        f.amount,
        d.tier,
        d.fee_rate_bps,
        ROW_NUMBER() OVER (
            PARTITION BY f.txn_id
            ORDER BY d.valid_from DESC, d.scd_key DESC
        ) AS rn
    FROM fact_transactions f
    LEFT JOIN dim_merchant_scd2 d
      ON f.merchant_id   = d.merchant_id
     AND f.txn_timestamp >= d.valid_from
     AND f.txn_timestamp <  d.valid_to
)
SELECT
    txn_id,
    merchant_id,
    txn_timestamp,
    amount,
    COALESCE(tier, 'UNKNOWN') AS tier,
    fee_rate_bps,
    ROUND(amount * fee_rate_bps / 10000.0, 2) AS fee_amount
FROM matched
WHERE rn = 1
ORDER BY txn_id;
```

### Why This Is Better

| Dimension | Correlated Subqueries | Optimal (Half-Open `LEFT JOIN`) |
|-----------|-----------------------|---------------------------------|
| **Execution plan** | $3\times$ nested loop / subquery probes per row | Single hash/merge/range join over `(merchant_id, valid_from, valid_to)` |
| **Boundary safety** | Safe, but slow | Exact `[valid_from, valid_to)` prevents double-counting (`1002`, `1004`) |
| **Missing history safety** | Preserves fact rows | `LEFT JOIN` preserves pre-history (`1005`) and unknown merchants (`1007`) |
| **Multi-column enrichment** | Duplicates subquery per column | Pulls all SCD2 columns in one join |

---

## Interviewer Follow-Up Questions

### 1. "On a 10-billion-row `fact_transactions` table in Spark / Snowflake / BigQuery, inequality range joins (`>=` and `<`) are notoriously slow (often causing O(N × M) per key or broadcast spills). How do you optimize this?"

1. **Use native `ASOF JOIN` if supported** (Snowflake, DuckDB, ClickHouse, Kusto):
   ```sql
   SELECT f.*, COALESCE(d.tier, 'UNKNOWN') AS tier, d.fee_rate_bps
   FROM fact_transactions f
   ASOF JOIN dim_merchant_scd2 d
     MATCH_CONDITION (f.txn_timestamp >= d.valid_from)
     ON f.merchant_id = d.merchant_id;
   ```
   `ASOF JOIN` uses a single binary-search / sort-merge scan per key in $O((N + M) \log M)$ instead of evaluating full inequality ranges! (Check carefully whether `ASOF JOIN` ignores `valid_to` gaps if a merchant can churn and become inactive.)
2. **Temporal Bucketing (for Spark / BigQuery)**: Bucket `[valid_from, valid_to)` into `event_date` (or month) partitions so the join includes an **equality condition** `ON f.merchant_id = d.merchant_id AND f.txn_date = d.bucket_date`, turning an inequality join into a fast partitioned hash join!

### 2. "What if `fact_transactions` row `1005` arrived *before* the merchant's onboarding SCD2 record due to clock skew (e.g., `02-05` vs `02-10`), and Finance wants to backfill it with the merchant's earliest known tier instead of `'UNKNOWN'`?"

In a separate `COALESCE` fallback or `ASOF` lookahead, join to the `MIN(valid_from)` row per `merchant_id` when the standard point-in-time `LEFT JOIN` yields `NULL`:
```sql
LEFT JOIN (
    SELECT * FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY merchant_id ORDER BY valid_from ASC) AS rn
        FROM dim_merchant_scd2
    ) x WHERE rn = 1
) earliest
  ON f.merchant_id = earliest.merchant_id
 AND d.scd_key IS NULL
```
Then use `COALESCE(d.tier, earliest.tier, 'UNKNOWN')`.

### 3. "How do you validate in CI/dbt tests that `dim_merchant_scd2` has no overlapping intervals before this join runs?"

Run an overlap assertion test (zero rows expected):
```sql
SELECT a.merchant_id, a.scd_key, b.scd_key
FROM dim_merchant_scd2 a
JOIN dim_merchant_scd2 b
  ON a.merchant_id = b.merchant_id
 AND a.scd_key < b.scd_key
 AND a.valid_from < b.valid_to
 AND b.valid_from < a.valid_to;
```
Also verify no gaps exist between consecutive versions (`LEAD(valid_from) OVER (...) = valid_to`).

---

## Key Takeaways

- 📌 **Always use half-open intervals** (`txn_timestamp >= valid_from AND txn_timestamp < valid_to`) for SCD Type 2 joins — **never `BETWEEN`**, which double-counts boundary events
- 📌 **Use `LEFT JOIN`, never `INNER JOIN`**, when joining facts to dimensions so backdated or unknown-key facts aren't silently dropped from financial totals
- 📌 When `dim_merchant_scd2` might contain overlapping dirty rows, add **`ROW_NUMBER() OVER (PARTITION BY txn_id ...)`** as a defensive fan-out guard
- 📌 Know the **two big-data optimizations** for range joins: **`ASOF JOIN`** (Snowflake/DuckDB) and **date-bucketing equality keys** (Spark/BigQuery)
- 📌 Validate SCD2 integrity (`no overlaps`, `no gaps`, `exactly one is_current = TRUE per key`) upstream so temporal joins stay exact
