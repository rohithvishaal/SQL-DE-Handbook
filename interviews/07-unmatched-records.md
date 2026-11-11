# 07 — Finding Unmatched Records Across Two Massive Tables

## Difficulty

**Medium**

## Companies

Amazon · Apple · Microsoft · Google

---

## Problem Statement

You are a data engineer at a large e-commerce company. Two independent systems produce order data: the **order management system** (`orders`) and the **payment processing system** (`payments`). Due to network failures, retry logic, and eventual consistency, some orders exist without a corresponding payment record and vice versa. Your task is to perform a **reconciliation**: find all orders that have no matching payment and all payments that have no matching order.

The tables are massive (hundreds of millions of rows each), so your solution must be efficient. Write a query that returns every unmatched record from both sides, labeled by which system it came from.

---

## Schema DDL

```sql
CREATE TABLE orders (
    order_id      VARCHAR(20) PRIMARY KEY,
    customer_id   INT NOT NULL,
    order_amount  DECIMAL(10,2) NOT NULL,
    order_date    DATE NOT NULL,
    status        VARCHAR(20) NOT NULL
);

CREATE TABLE payments (
    payment_id    VARCHAR(20) PRIMARY KEY,
    order_id      VARCHAR(20) NOT NULL,
    payment_amount DECIMAL(10,2) NOT NULL,
    payment_date  DATE NOT NULL,
    payment_method VARCHAR(20) NOT NULL
);

INSERT INTO orders (order_id, customer_id, order_amount, order_date, status) VALUES
('ORD-001', 1001, 150.00, '2024-06-01', 'completed'),
('ORD-002', 1002, 89.99,  '2024-06-01', 'completed'),
('ORD-003', 1003, 245.50, '2024-06-02', 'completed'),
('ORD-004', 1004, 32.00,  '2024-06-02', 'pending'),
('ORD-005', 1005, 178.75, '2024-06-03', 'completed'),
('ORD-006', 1006, 410.00, '2024-06-03', 'completed'),
('ORD-007', 1007, 67.50,  '2024-06-04', 'cancelled'),
('ORD-008', 1008, 299.99, '2024-06-04', 'completed'),
('ORD-009', 1009, 55.00,  '2024-06-05', 'completed'),
('ORD-010', 1010, 125.00, '2024-06-05', 'completed'),
('ORD-011', 1011, 88.00,  '2024-06-06', 'completed'),
('ORD-012', 1012, 340.00, '2024-06-06', 'completed'),
('ORD-013', 1013, 72.25,  '2024-06-07', 'pending'),
('ORD-014', 1014, 199.99, '2024-06-07', 'completed'),
('ORD-015', 1015, 450.00, '2024-06-08', 'completed');

INSERT INTO payments (payment_id, order_id, payment_amount, payment_date, payment_method) VALUES
('PAY-001', 'ORD-001', 150.00, '2024-06-01', 'credit_card'),
('PAY-002', 'ORD-002', 89.99,  '2024-06-01', 'debit_card'),
('PAY-003', 'ORD-003', 245.50, '2024-06-02', 'credit_card'),
('PAY-004', 'ORD-005', 178.75, '2024-06-03', 'paypal'),
('PAY-005', 'ORD-006', 410.00, '2024-06-03', 'credit_card'),
('PAY-006', 'ORD-008', 299.99, '2024-06-04', 'credit_card'),
('PAY-007', 'ORD-009', 55.00,  '2024-06-05', 'debit_card'),
('PAY-008', 'ORD-010', 125.00, '2024-06-05', 'paypal'),
('PAY-009', 'ORD-011', 88.00,  '2024-06-06', 'credit_card'),
('PAY-010', 'ORD-014', 199.99, '2024-06-07', 'credit_card'),
('PAY-011', 'ORD-015', 450.00, '2024-06-08', 'debit_card'),
('PAY-012', 'ORD-099', 500.00, '2024-06-08', 'credit_card'),   -- orphan payment
('PAY-013', 'ORD-098', 75.00,  '2024-06-09', 'paypal'),        -- orphan payment
('PAY-014', 'ORD-097', 310.00, '2024-06-09', 'credit_card');    -- orphan payment
```

---

## Sample Input

### orders

| order_id | customer_id | order_amount | order_date | status    |
|----------|-------------|-------------|------------|-----------|
| ORD-001  | 1001        | 150.00      | 2024-06-01 | completed |
| ORD-002  | 1002        | 89.99       | 2024-06-01 | completed |
| ORD-003  | 1003        | 245.50      | 2024-06-02 | completed |
| ORD-004  | 1004        | 32.00       | 2024-06-02 | pending   |
| ORD-005  | 1005        | 178.75      | 2024-06-03 | completed |
| ORD-006  | 1006        | 410.00      | 2024-06-03 | completed |
| ORD-007  | 1007        | 67.50       | 2024-06-04 | cancelled |
| ORD-008  | 1008        | 299.99      | 2024-06-04 | completed |
| ORD-009  | 1009        | 55.00       | 2024-06-05 | completed |
| ORD-010  | 1010        | 125.00      | 2024-06-05 | completed |
| ORD-011  | 1011        | 88.00       | 2024-06-06 | completed |
| ORD-012  | 1012        | 340.00      | 2024-06-06 | completed |
| ORD-013  | 1013        | 72.25       | 2024-06-07 | pending   |
| ORD-014  | 1014        | 199.99      | 2024-06-07 | completed |
| ORD-015  | 1015        | 450.00      | 2024-06-08 | completed |

### payments

| payment_id | order_id | payment_amount | payment_date | payment_method |
|------------|----------|---------------|--------------|----------------|
| PAY-001    | ORD-001  | 150.00        | 2024-06-01   | credit_card    |
| PAY-002    | ORD-002  | 89.99         | 2024-06-01   | debit_card     |
| PAY-003    | ORD-003  | 245.50        | 2024-06-02   | credit_card    |
| PAY-004    | ORD-005  | 178.75        | 2024-06-03   | paypal         |
| PAY-005    | ORD-006  | 410.00        | 2024-06-03   | credit_card    |
| PAY-006    | ORD-008  | 299.99        | 2024-06-04   | credit_card    |
| PAY-007    | ORD-009  | 55.00         | 2024-06-05   | debit_card     |
| PAY-008    | ORD-010  | 125.00        | 2024-06-05   | paypal         |
| PAY-009    | ORD-011  | 88.00         | 2024-06-06   | credit_card    |
| PAY-010    | ORD-014  | 199.99        | 2024-06-07   | credit_card    |
| PAY-011    | ORD-015  | 450.00        | 2024-06-08   | debit_card     |
| PAY-012    | ORD-099  | 500.00        | 2024-06-08   | credit_card    |
| PAY-013    | ORD-098  | 75.00         | 2024-06-09   | paypal         |
| PAY-014    | ORD-097  | 310.00        | 2024-06-09   | credit_card    |

---

## Expected Output

| source_system | record_id | order_id | amount | record_date | details              |
|---------------|-----------|----------|--------|-------------|----------------------|
| orders        | ORD-004   | ORD-004  | 32.00  | 2024-06-02  | status=pending       |
| orders        | ORD-007   | ORD-007  | 67.50  | 2024-06-04  | status=cancelled     |
| orders        | ORD-012   | ORD-012  | 340.00 | 2024-06-06  | status=completed     |
| orders        | ORD-013   | ORD-013  | 72.25  | 2024-06-07  | status=pending       |
| payments      | PAY-012   | ORD-099  | 500.00 | 2024-06-08  | method=credit_card   |
| payments      | PAY-013   | ORD-098  | 75.00  | 2024-06-09  | method=paypal        |
| payments      | PAY-014   | ORD-097  | 310.00 | 2024-06-09  | method=credit_card   |

---

## Brute Force Solution

The most intuitive approach uses a **FULL OUTER JOIN** and filters for rows where one side is `NULL`.

```sql
-- Brute Force: FULL OUTER JOIN
SELECT
    CASE
        WHEN p.payment_id IS NULL THEN 'orders'
        ELSE 'payments'
    END AS source_system,
    COALESCE(o.order_id, p.payment_id) AS record_id,
    COALESCE(o.order_id, p.order_id)   AS order_id,
    COALESCE(o.order_amount, p.payment_amount) AS amount,
    COALESCE(o.order_date, p.payment_date)     AS record_date,
    CASE
        WHEN p.payment_id IS NULL THEN 'status=' || o.status
        ELSE 'method=' || p.payment_method
    END AS details
FROM orders o
FULL OUTER JOIN payments p
    ON o.order_id = p.order_id
WHERE o.order_id IS NULL        -- payment without matching order
   OR p.payment_id IS NULL      -- order without matching payment
ORDER BY source_system, record_id;
```

### Step-by-Step Explanation

1. **FULL OUTER JOIN** produces all rows from both tables, matching on `order_id`.
2. Where there is **no match**, one side's columns are `NULL`.
3. The `WHERE` clause keeps only the unmatched rows from either side.
4. `COALESCE` selects the non-null value from whichever side has data.

> **Drawback**: `FULL OUTER JOIN` on massive tables is expensive — the engine must hash or sort *both* entire tables, even though we only want the unmatched minority. Many engines (especially older ones) do not optimize FULL OUTER JOIN as well as LEFT/ANTI joins.

---

## Optimal Solution

Use **two separate anti-join queries** combined with `UNION ALL`. Anti-joins (via `LEFT JOIN … WHERE IS NULL` or `NOT EXISTS`) are highly optimized in all major engines and allow each side to use its own indexes independently.

```sql
-- Optimal: Anti-Join with UNION ALL

-- Orders without a matching payment
SELECT
    'orders'          AS source_system,
    o.order_id        AS record_id,
    o.order_id        AS order_id,
    o.order_amount    AS amount,
    o.order_date      AS record_date,
    'status=' || o.status AS details
FROM orders o
LEFT JOIN payments p
    ON o.order_id = p.order_id
WHERE p.order_id IS NULL

UNION ALL

-- Payments without a matching order
SELECT
    'payments'         AS source_system,
    p.payment_id       AS record_id,
    p.order_id         AS order_id,
    p.payment_amount   AS amount,
    p.payment_date     AS record_date,
    'method=' || p.payment_method AS details
FROM payments p
LEFT JOIN orders o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL

ORDER BY source_system, record_id;
```

### Alternative with `NOT EXISTS` (equally optimal)

```sql
-- Using NOT EXISTS (correlated subquery — equally performant with indexes)

SELECT
    'orders'          AS source_system,
    o.order_id        AS record_id,
    o.order_id        AS order_id,
    o.order_amount    AS amount,
    o.order_date      AS record_date,
    'status=' || o.status AS details
FROM orders o
WHERE NOT EXISTS (
    SELECT 1 FROM payments p WHERE p.order_id = o.order_id
)

UNION ALL

SELECT
    'payments'         AS source_system,
    p.payment_id       AS record_id,
    p.order_id         AS order_id,
    p.payment_amount   AS amount,
    p.payment_date     AS record_date,
    'method=' || p.payment_method AS details
FROM payments p
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.order_id = p.order_id
)

ORDER BY source_system, record_id;
```

### Why This Is Better

| Aspect | FULL OUTER JOIN | Anti-Join (LEFT JOIN / NOT EXISTS) |
|--------|-----------------|-----------------------------------|
| **Index usage** | Often poor — requires full hash/sort of both tables | Excellent — each side uses its own index on `order_id` |
| **Memory** | Must build a hash table for the full join of both tables | Each anti-join only needs the smaller hash or can use index lookups |
| **Parallelism** | Single operator; hard to parallelize | Two independent queries; can run in parallel, then UNION ALL |
| **Engine support** | FULL OUTER JOIN not supported in MySQL; suboptimal in many engines | Anti-joins are universally well-optimized |
| **Readability** | Single query but complex COALESCE logic | Each half is straightforward and testable independently |

> [!TIP]
> Always ensure `order_id` is indexed on both tables. For the payments table, if `order_id` is not the primary key, add a B-tree index: `CREATE INDEX idx_payments_order_id ON payments(order_id);`

---

## Interviewer Follow-Up Questions

1. **"What if there can be multiple payments per order? How do you find orders that are partially paid?"**
   - Use a `LEFT JOIN` with `GROUP BY` and compare `SUM(payment_amount)` against `order_amount`. Unmatched orders have `SUM = NULL` (no payments), and partially paid orders have `SUM < order_amount`. This transforms the reconciliation from a set-membership problem into an aggregation problem.

2. **"The tables have 500M rows each and the query runs out of memory. How do you optimize?"**
   - **Partition both tables** by date and run the reconciliation per-partition (e.g., daily). Use `EXCEPT` / `MINUS` on just the key column to get the unmatched key set, then join back for details. In Spark/BigQuery, consider a **broadcast join** if the unmatched set is small. Also consider **Bloom filter** pre-filtering to quickly eliminate rows that definitely have matches.

3. **"How would you handle this as a recurring daily data quality check?"**
   - Build an incremental reconciliation pipeline: only check records from the last N days (using `WHERE order_date >= CURRENT_DATE - INTERVAL '3' DAY`). Store results in an `unmatched_records` table with `detected_date` and `resolved_date`. Alert on new unmatched records via a monitoring dashboard. Implement auto-retry logic for records that resolve within the SLA window.

---

## Key Takeaways

- **Anti-joins** (`LEFT JOIN … WHERE IS NULL` or `NOT EXISTS`) are the most efficient way to find unmatched records. Prefer them over `FULL OUTER JOIN` for large tables.
- **`NOT IN`** should be avoided — it has dangerous `NULL` semantics (if any value in the subquery is `NULL`, the entire `NOT IN` returns no rows). Always use `NOT EXISTS` instead.
- **`EXCEPT`** is a clean set-operation alternative for finding unmatched keys, but you lose access to other columns and must join back.
- **Indexing the join key** on both tables is the single most important performance optimization.
- **UNION ALL** (not `UNION`) should be used when combining the two sides — there cannot be duplicates across the two halves since they come from different source systems.
- In production, unmatched-record reconciliation is a **core data quality pattern** — build it as an incremental, partitioned, scheduled pipeline.
