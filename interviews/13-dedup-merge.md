# Deduplication with Priority Rules and MERGE Upserts

## Difficulty

🟡 **Medium**

## Companies

Snowflake, Databricks, Netflix, Airbnb, Stripe, Uber

---

## Problem Statement

You are a Data Engineer maintaining a customer profile dimension table (`dim_customers`) in a cloud data warehouse. Upstream microservices emit change events into a staging table (`stg_customer_events`) via Kafka and CDC pipelines. Because of network retries, out-of-order delivery, and multiple source systems (`checkout_svc`, `mobile_app`, `crm_manual`), the staging batch frequently contains **multiple records for the same `customer_id`**.

Before loading `dim_customers`, you must:
1. **Deduplicate** `stg_customer_events` to keep exactly **one winning record per `customer_id`** using deterministic priority rules:
   - **Latest `updated_at` wins**.
   - If timestamps tie, **source system precedence** breaks the tie (`crm_manual` > `checkout_svc` > `mobile_app`).
   - If still tied, highest **`event_seq`** wins.
2. **Idempotently upsert** the deduplicated records into `dim_customers` using `MERGE INTO`:
   - If the winning record is a `DELETE` (`is_deleted = TRUE`), mark the target row as deleted (soft delete) or delete it.
   - If the target row exists and is older than the incoming event (`target.updated_at < source.updated_at`), update it.
   - If the target row does not exist and is not a delete, insert it.
   - Never let stale late-arriving staging events overwrite newer target rows!

---

## Schema DDL

```sql
CREATE TABLE dim_customers (
    customer_id   INT PRIMARY KEY,
    email         VARCHAR(100) NOT NULL,
    tier          VARCHAR(20)  NOT NULL,
    source_system VARCHAR(30)  NOT NULL,
    is_deleted    BOOLEAN      NOT NULL DEFAULT FALSE,
    updated_at    TIMESTAMP    NOT NULL
);

CREATE TABLE stg_customer_events (
    event_seq     BIGINT PRIMARY KEY,
    customer_id   INT          NOT NULL,
    email         VARCHAR(100) NOT NULL,
    tier          VARCHAR(20)  NOT NULL,
    source_system VARCHAR(30)  NOT NULL,
    op_type       VARCHAR(10)  NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
    updated_at    TIMESTAMP    NOT NULL
);

-- Existing target state before today's batch
INSERT INTO dim_customers (customer_id, email, tier, source_system, is_deleted, updated_at) VALUES
(101, 'alice@old.com',   'Silver', 'mobile_app',   FALSE, '2025-02-01 09:00:00'),
(102, 'bob@mail.com',    'Gold',   'checkout_svc', FALSE, '2025-02-01 12:00:00'),
(103, 'carol@mail.com',  'Bronze', 'mobile_app',   FALSE, '2025-02-01 10:00:00');

-- Incoming staging batch with duplicates, timestamp ties, late arrivals, and deletes
INSERT INTO stg_customer_events (event_seq, customer_id, email, tier, source_system, op_type, updated_at) VALUES
-- Customer 101: Two updates at different times; 11:00 wins over 10:00
(1001, 101, 'alice@new.com',  'Silver', 'mobile_app',   'UPDATE', '2025-02-01 10:00:00'),
(1002, 101, 'alice@new.com',  'Gold',   'checkout_svc', 'UPDATE', '2025-02-01 11:00:00'),
-- Customer 102: Late-arriving event (08:00) is OLDER than target (12:00) -> MUST NOT overwrite target!
(1003, 102, 'bob@stale.com',  'Silver', 'mobile_app',   'UPDATE', '2025-02-01 08:00:00'),
-- Customer 103: Exact timestamp tie (14:00) across 3 sources; crm_manual wins over checkout_svc > mobile_app
(1004, 103, 'carol@app.com',  'Bronze', 'mobile_app',   'UPDATE', '2025-02-01 14:00:00'),
(1005, 103, 'carol@chk.com',  'Silver', 'checkout_svc', 'UPDATE', '2025-02-01 14:00:00'),
(1006, 103, 'carol@vip.com',  'Gold',   'crm_manual',   'UPDATE', '2025-02-01 14:00:00'),
-- Customer 104: New customer inserted twice with exact same source & timestamp -> highest event_seq (1008) wins
(1007, 104, 'dave@mail.com',  'Bronze', 'mobile_app',   'INSERT', '2025-02-01 15:00:00'),
(1008, 104, 'dave@mail.com',  'Silver', 'mobile_app',   'UPDATE', '2025-02-01 15:00:00'),
-- Customer 105: Inserted then deleted in same batch -> DELETE wins, should not create active row
(1009, 105, 'eve@mail.com',   'Bronze', 'mobile_app',   'INSERT', '2025-02-01 16:00:00'),
(1010, 105, 'eve@mail.com',   'Bronze', 'crm_manual',   'DELETE', '2025-02-01 16:05:00');
```

---

## Sample Input

**dim_customers (before MERGE)**

| customer_id | email         | tier   | source_system | is_deleted | updated_at          |
|-------------|---------------|--------|---------------|------------|---------------------|
| 101         | alice@old.com | Silver | mobile_app    | FALSE      | 2025-02-01 09:00:00 |
| 102         | bob@mail.com  | Gold   | checkout_svc  | FALSE      | 2025-02-01 12:00:00 |
| 103         | carol@mail.com| Bronze | mobile_app    | FALSE      | 2025-02-01 10:00:00 |

**stg_customer_events**

| event_seq | customer_id | email         | tier   | source_system | op_type | updated_at          |
|-----------|-------------|---------------|--------|---------------|---------|---------------------|
| 1001      | 101         | alice@new.com | Silver | mobile_app    | UPDATE  | 2025-02-01 10:00:00 |
| 1002      | 101         | alice@new.com | Gold   | checkout_svc  | UPDATE  | 2025-02-01 11:00:00 |
| 1003      | 102         | bob@stale.com | Silver | mobile_app    | UPDATE  | 2025-02-01 08:00:00 |
| 1004      | 103         | carol@app.com | Bronze | mobile_app    | UPDATE  | 2025-02-01 14:00:00 |
| 1005      | 103         | carol@chk.com | Silver | checkout_svc  | UPDATE  | 2025-02-01 14:00:00 |
| 1006      | 103         | carol@vip.com | Gold   | crm_manual    | UPDATE  | 2025-02-01 14:00:00 |
| 1007      | 104         | dave@mail.com | Bronze | mobile_app    | INSERT  | 2025-02-01 15:00:00 |
| 1008      | 104         | dave@mail.com | Silver | mobile_app    | UPDATE  | 2025-02-01 15:00:00 |
| 1009      | 105         | eve@mail.com  | Bronze | mobile_app    | INSERT  | 2025-02-01 16:00:00 |
| 1010      | 105         | eve@mail.com  | Bronze | crm_manual    | DELETE  | 2025-02-01 16:05:00 |

---

## Expected Output

**dim_customers (after MERGE)**

| customer_id | email         | tier   | source_system | is_deleted | updated_at          |
|-------------|---------------|--------|---------------|------------|---------------------|
| 101         | alice@new.com | Gold   | checkout_svc  | FALSE      | 2025-02-01 11:00:00 |
| 102         | bob@mail.com  | Gold   | checkout_svc  | FALSE      | 2025-02-01 12:00:00 |
| 103         | carol@vip.com | Gold   | crm_manual    | FALSE      | 2025-02-01 14:00:00 |
| 104         | dave@mail.com | Silver | mobile_app    | FALSE      | 2025-02-01 15:00:00 |

> [!NOTE]
> - **Customer 101**: Updated to `11:00` (`checkout_svc`, Gold).
> - **Customer 102**: Ignored stale `08:00` event because target already has `12:00`.
> - **Customer 103**: Tie at `14:00` broken by source precedence (`crm_manual` > `checkout_svc` > `mobile_app`).
> - **Customer 104**: Tie at `15:00` & `mobile_app` broken by `event_seq = 1008`.
> - **Customer 105**: Latest op in batch is `DELETE` and customer didn't exist in target, so no active row is inserted.

---

## Brute Force Solution

**Approach: Multi-step correlated `MAX()` staging cleanup + separate `UPDATE` and `INSERT` statements**

Without window functions or `MERGE`, engineers often write multiple passes over staging (first finding `MAX(updated_at)`, then breaking ties with `MAX(priority)`, then `MAX(event_seq)`), followed by non-atomic `DELETE`/`UPDATE`/`INSERT` statements.

```sql
-- Step 1: Materialize deduped staging via cascading MAX aggregations
CREATE TEMP TABLE stg_deduped AS
WITH max_ts AS (
    SELECT customer_id, MAX(updated_at) AS max_updated_at
    FROM stg_customer_events
    GROUP BY customer_id
),
with_priority AS (
    SELECT
        s.*,
        CASE s.source_system
            WHEN 'crm_manual'   THEN 3
            WHEN 'checkout_svc' THEN 2
            WHEN 'mobile_app'   THEN 1
            ELSE 0
        END AS src_priority
    FROM stg_customer_events s
    JOIN max_ts m
      ON s.customer_id = m.customer_id
     AND s.updated_at  = m.max_updated_at
),
max_prio AS (
    SELECT customer_id, MAX(src_priority) AS max_src_priority
    FROM with_priority
    GROUP BY customer_id
),
max_seq AS (
    SELECT wp.customer_id, MAX(wp.event_seq) AS win_seq
    FROM with_priority wp
    JOIN max_prio mp
      ON wp.customer_id  = mp.customer_id
     AND wp.src_priority = mp.max_src_priority
    GROUP BY wp.customer_id
)
SELECT wp.*
FROM with_priority wp
JOIN max_seq ms ON wp.event_seq = ms.win_seq;

-- Step 2: Update existing rows (guarded against stale updates)
UPDATE dim_customers d
SET
    email         = s.email,
    tier          = s.tier,
    source_system = s.source_system,
    is_deleted    = (s.op_type = 'DELETE'),
    updated_at    = s.updated_at
FROM stg_deduped s
WHERE d.customer_id = s.customer_id
  AND d.updated_at  < s.updated_at;

-- Step 3: Insert new non-deleted rows
INSERT INTO dim_customers (customer_id, email, tier, source_system, is_deleted, updated_at)
SELECT s.customer_id, s.email, s.tier, s.source_system, FALSE, s.updated_at
FROM stg_deduped s
WHERE s.op_type <> 'DELETE'
  AND NOT EXISTS (
      SELECT 1 FROM dim_customers d WHERE d.customer_id = s.customer_id
  );
```

**Explanation:**
1. Three cascading `GROUP BY` + `JOIN` steps narrow down to the single winning `event_seq` per `customer_id`.
2. Separate `UPDATE` and `INSERT` statements mutate `dim_customers`.

**Drawbacks:**
- **4 full passes over staging** (`max_ts`, `with_priority`, `max_prio`, `max_seq`).
- **Two separate passes over `dim_customers`** (`UPDATE` + `INSERT`) — without an explicit transaction, a failure between `UPDATE` and `INSERT` leaves the table partially applied (not atomic).
- **Verbose and error-prone** as tie-breaker rules grow.

---

## Optimal Solution

**Approach: Single-pass `ROW_NUMBER()` deduplication + atomic `MERGE INTO`**

We compute a deterministic rank in one pass over `stg_customer_events` using a composite `ORDER BY` inside `ROW_NUMBER()`, then feed only `rn = 1` into a single atomic `MERGE INTO` statement.

```sql
MERGE INTO dim_customers AS tgt
USING (
    SELECT
        customer_id,
        email,
        tier,
        source_system,
        op_type,
        updated_at
    FROM (
        SELECT
            e.*,
            ROW_NUMBER() OVER (
                PARTITION BY e.customer_id
                ORDER BY
                    e.updated_at DESC,
                    CASE e.source_system
                        WHEN 'crm_manual'   THEN 3
                        WHEN 'checkout_svc' THEN 2
                        WHEN 'mobile_app'   THEN 1
                        ELSE 0
                    END DESC,
                    e.event_seq DESC
            ) AS rn
        FROM stg_customer_events e
    ) ranked
    WHERE rn = 1
) AS src
ON tgt.customer_id = src.customer_id

-- 1. Existing customer receives a newer DELETE event -> soft delete
WHEN MATCHED AND src.op_type = 'DELETE' AND tgt.updated_at < src.updated_at THEN
    UPDATE SET
        is_deleted    = TRUE,
        source_system = src.source_system,
        updated_at    = src.updated_at

-- 2. Existing customer receives a newer INSERT/UPDATE -> overwrite with latest state
WHEN MATCHED AND src.op_type <> 'DELETE' AND tgt.updated_at < src.updated_at THEN
    UPDATE SET
        email         = src.email,
        tier          = src.tier,
        source_system = src.source_system,
        is_deleted    = FALSE,
        updated_at    = src.updated_at

-- 3. New customer (not deleted in same batch) -> insert
WHEN NOT MATCHED AND src.op_type <> 'DELETE' THEN
    INSERT (customer_id, email, tier, source_system, is_deleted, updated_at)
    VALUES (src.customer_id, src.email, src.tier, src.source_system, FALSE, src.updated_at);
```

> [!TIP]
> In engines that support `QUALIFY` (Snowflake, BigQuery, Databricks SQL, DuckDB, Teradata), the inner subquery simplifies cleanly to:
> ```sql
> SELECT customer_id, email, tier, source_system, op_type, updated_at
> FROM stg_customer_events
> QUALIFY ROW_NUMBER() OVER (
>     PARTITION BY customer_id
>     ORDER BY updated_at DESC,
>              CASE source_system WHEN 'crm_manual' THEN 3 WHEN 'checkout_svc' THEN 2 WHEN 'mobile_app' THEN 1 ELSE 0 END DESC,
>              event_seq DESC
> ) = 1
> ```

### Why This Is Better

| Dimension | Brute Force | Optimal (`ROW_NUMBER` + `MERGE`) |
|-----------|-------------|----------------------------------|
| **Staging scans** | 4 scans + 3 joins | 1 single sort/partition pass |
| **Target atomicity** | Non-atomic (`UPDATE` then `INSERT`) unless wrapped manually | Single atomic `MERGE` statement |
| **Duplicate source safety** | Risky if tie-breakers aren't strictly unique | `ROW_NUMBER()` guarantees at most 1 source row per key |
| **Extensibility** | Adding a 4th tie-breaker requires a new CTE | Add one expression to `ORDER BY` inside `OVER (...)` |

> [!WARNING]
> **`MERGE` Cardinality Violation Error**: In SQL (Snowflake, BigQuery, Postgres 15+, SQL Server), if the `USING` source contains **2 or more rows matching the same target row**, `MERGE` fails at runtime with an error (`"MERGE statement cannot affect the same row multiple times"` / `"Nondeterministic MERGE"`). Always deduplicate the `USING` subquery to `rn = 1` **before** merging!

---

## Interviewer Follow-Up Questions

### 1. "What happens if an incoming event has the exact same `updated_at` as an existing row in `dim_customers` (e.g., a partial replay)?"

In our query, we used `tgt.updated_at < src.updated_at`. If the same batch is replayed twice (idempotency check), `tgt.updated_at = src.updated_at` will be skipped — avoiding unnecessary micro-partition rewrites in Snowflake/Delta Lake. However, if `crm_manual` could arrive later with the *same* timestamp as an already-landed `mobile_app` row, change the guard to compare `(src.updated_at, src_priority)` against `(tgt.updated_at, tgt_priority)`.

### 2. "In a columnar data warehouse (Snowflake, BigQuery, Delta Lake), `MERGE` on a 10-billion-row target table can still be slow if it scans the whole table. How do you optimize it?"

1. **Cluster / Z-Order** the target table on `customer_id`.
2. **Dynamic Partition / Date Pruning**: If staging events only touch customers created or active in a known partition window, add a partition filter in the `ON` clause (e.g., `AND tgt.updated_at >= DATEADD(day, -7, CURRENT_DATE)` when business rules allow, or join against a narrow partition list extracted from staging) so the engine prunes 99% of untouched micro-partitions.

### 3. "How would you modify this if you had to handle partial updates (where `email` is `NULL` in an event meaning 'unchanged', rather than 'set to NULL')?"

In the `ROW_NUMBER()` step, you can't just keep one row — you need the latest non-null value per column! Use `LAST_VALUE(email IGNORE NULLS) OVER (PARTITION BY customer_id ORDER BY updated_at ... ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)` across the staging window, and in the `MERGE UPDATE` clause use `COALESCE(src.email, tgt.email)`.

---

## Key Takeaways

- 📌 **Always deduplicate the `USING` subquery** to 1 row per merge key (`ROW_NUMBER() ... = 1`) before `MERGE INTO` to avoid cardinality crashes
- 📌 Encode **deterministic priority tie-breakers** (`CASE` precedence + unique `event_seq`) inside `ROW_NUMBER() OVER (PARTITION BY key ORDER BY ...)`
- 📌 Guard `WHEN MATCHED` with **`tgt.updated_at < src.updated_at`** so out-of-order / late-arriving messages never regress current state, and batch re-runs remain **idempotent**
- 📌 Handle **deletes inside the same batch** cleanly: let `DELETE` win in ranking if newer, and skip `WHEN NOT MATCHED` inserts when `op_type = 'DELETE'`
- 📌 Use **soft deletes (`is_deleted = TRUE`)** rather than physical `DELETE` when late-arriving older events could otherwise re-insert a deleted entity
