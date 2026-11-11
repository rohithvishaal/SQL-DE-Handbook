# 06 — Identifying Fraudulent Ring / Circular Transactions

## Difficulty

**Hard**

## Companies

PayPal · Stripe · Square · Goldman Sachs

---

## Problem Statement

You work on the fraud detection team at a payments company. A common fraud pattern is **circular transactions** (also called "ring transactions"): User A sends money to User B, User B sends money to User C, and User C sends money back to User A — completing a cycle. These rings can involve 2, 3, or more participants and are used for money laundering, cash-out fraud, and synthetic identity schemes.

Given a table of peer-to-peer money transfers, write a query that identifies all **circular transaction chains of length 3** (i.e., three transfers that form a closed loop A→B→C→A) that occurred within a **24-hour window**. Return the user IDs involved and the total amount circulated in the ring.

---

## Schema DDL

```sql
CREATE TABLE transfers (
    transfer_id   INT PRIMARY KEY,
    sender_id     INT NOT NULL,
    receiver_id   INT NOT NULL,
    amount        DECIMAL(12,2) NOT NULL,
    transfer_ts   TIMESTAMP NOT NULL
);

INSERT INTO transfers (transfer_id, sender_id, receiver_id, amount, transfer_ts) VALUES
(1,  101, 102, 500.00,  '2024-03-15 08:00:00'),
(2,  102, 103, 480.00,  '2024-03-15 10:30:00'),
(3,  103, 101, 475.00,  '2024-03-15 14:00:00'),   -- closes ring 101→102→103→101
(4,  201, 202, 1000.00, '2024-03-15 09:00:00'),
(5,  202, 201, 990.00,  '2024-03-15 09:15:00'),   -- 2-node ring (not length-3)
(6,  301, 302, 200.00,  '2024-03-15 06:00:00'),
(7,  302, 303, 195.00,  '2024-03-15 07:00:00'),
(8,  303, 301, 190.00,  '2024-03-16 20:00:00'),   -- too far apart (>24h)
(9,  401, 402, 750.00,  '2024-03-16 12:00:00'),
(10, 402, 403, 740.00,  '2024-03-16 13:00:00'),
(11, 403, 401, 730.00,  '2024-03-16 14:30:00'),   -- closes ring 401→402→403→401
(12, 101, 501, 100.00,  '2024-03-15 16:00:00'),   -- noise
(13, 502, 101, 50.00,   '2024-03-15 17:00:00'),   -- noise
(14, 402, 404, 300.00,  '2024-03-16 15:00:00'),   -- noise
(15, 601, 602, 850.00,  '2024-03-17 08:00:00');   -- noise, no ring
```

---

## Sample Input

### transfers

| transfer_id | sender_id | receiver_id | amount  | transfer_ts         |
|-------------|-----------|-------------|---------|---------------------|
| 1           | 101       | 102         | 500.00  | 2024-03-15 08:00:00 |
| 2           | 102       | 103         | 480.00  | 2024-03-15 10:30:00 |
| 3           | 103       | 101         | 475.00  | 2024-03-15 14:00:00 |
| 4           | 201       | 202         | 1000.00 | 2024-03-15 09:00:00 |
| 5           | 202       | 201         | 990.00  | 2024-03-15 09:15:00 |
| 6           | 301       | 302         | 200.00  | 2024-03-15 06:00:00 |
| 7           | 302       | 303         | 195.00  | 2024-03-15 07:00:00 |
| 8           | 303       | 301         | 190.00  | 2024-03-16 20:00:00 |
| 9           | 401       | 402         | 750.00  | 2024-03-16 12:00:00 |
| 10          | 402       | 403         | 740.00  | 2024-03-16 13:00:00 |
| 11          | 403       | 401         | 730.00  | 2024-03-16 14:30:00 |
| 12          | 101       | 501         | 100.00  | 2024-03-15 16:00:00 |
| 13          | 502       | 101         | 50.00   | 2024-03-15 17:00:00 |
| 14          | 402       | 404         | 300.00  | 2024-03-16 15:00:00 |
| 15          | 601       | 602         | 850.00  | 2024-03-17 08:00:00 |

---

## Expected Output

| user_a | user_b | user_c | leg1_amount | leg2_amount | leg3_amount | total_circulated | ring_start_ts       | ring_end_ts         |
|--------|--------|--------|-------------|-------------|-------------|------------------|---------------------|---------------------|
| 101    | 102    | 103    | 500.00      | 480.00      | 475.00      | 1455.00          | 2024-03-15 08:00:00 | 2024-03-15 14:00:00 |
| 401    | 402    | 403    | 750.00      | 740.00      | 730.00      | 2220.00          | 2024-03-16 12:00:00 | 2024-03-16 14:30:00 |

---

## Brute Force Solution

The straightforward approach is a **triple self-join** — join the transfers table to itself three times, chaining `receiver_id` to `sender_id` and checking that the final receiver equals the first sender.

```sql
-- Brute Force: Triple Self-Join
SELECT
    t1.sender_id   AS user_a,
    t2.sender_id   AS user_b,
    t3.sender_id   AS user_c,
    t1.amount       AS leg1_amount,
    t2.amount       AS leg2_amount,
    t3.amount       AS leg3_amount,
    t1.amount + t2.amount + t3.amount AS total_circulated,
    t1.transfer_ts  AS ring_start_ts,
    t3.transfer_ts  AS ring_end_ts
FROM transfers t1
JOIN transfers t2
    ON t1.receiver_id = t2.sender_id          -- A→B then B→...
   AND t2.transfer_ts > t1.transfer_ts        -- chronological order
JOIN transfers t3
    ON t2.receiver_id = t3.sender_id          -- B→C then C→...
   AND t3.receiver_id = t1.sender_id          -- C→A  (closes the ring)
   AND t3.transfer_ts > t2.transfer_ts        -- chronological order
WHERE t3.transfer_ts <= t1.transfer_ts + INTERVAL '24' HOUR   -- within 24h window
  AND t1.sender_id < t2.sender_id             -- canonical ordering to avoid duplicates
ORDER BY ring_start_ts;
```

### Step-by-Step Explanation

1. **First join (`t1 → t2`)**: Find pairs where t1's receiver is t2's sender — this chains leg 1 to leg 2. Enforce chronological order (`t2.transfer_ts > t1.transfer_ts`).
2. **Second join (`t2 → t3`)**: Find the third leg where t2's receiver is t3's sender. The cycle-closing condition is `t3.receiver_id = t1.sender_id`.
3. **24-hour constraint**: Ensure the entire ring completes within 24 hours of the first leg.
4. **Deduplication**: `t1.sender_id < t2.sender_id` ensures each ring is reported exactly once (canonical ordering of the first two nodes).

> **Drawback**: The triple self-join produces an O(n³) cross-product in the worst case. On a table with millions of transfers, this is extremely expensive — each intermediate join can explode the row count before the final filter prunes non-rings.

---

## Optimal Solution

Use a **recursive CTE** that walks the graph up to depth 3, tracking the path and pruning early. This approach generalizes to rings of any length and lets the optimizer prune dead-end paths without materializing all O(n³) combinations.

```sql
-- Optimal: Recursive CTE Graph Walk
WITH RECURSIVE ring_walk AS (
    -- Anchor: every transfer is a potential ring start
    SELECT
        t.transfer_id                          AS start_transfer_id,
        t.sender_id                            AS ring_origin,
        t.receiver_id                          AS current_node,
        1                                      AS depth,
        CAST(t.amount AS NUMERIC(18, 2))       AS total_amount,
        t.transfer_ts                          AS ring_start_ts,
        t.transfer_ts                          AS last_ts,
        CAST(t.sender_id AS VARCHAR(200))      AS path
    FROM transfers t

    UNION ALL

    -- Recursive step: extend the chain by one hop
    SELECT
        rw.start_transfer_id,
        rw.ring_origin,
        t.receiver_id                          AS current_node,
        rw.depth + 1                           AS depth,
        CAST(rw.total_amount + t.amount AS NUMERIC(18, 2)) AS total_amount,
        rw.ring_start_ts,
        t.transfer_ts                          AS last_ts,
        CAST(rw.path || '→' || CAST(t.sender_id AS VARCHAR(20)) AS VARCHAR(200)) AS path
    FROM ring_walk rw
    JOIN transfers t
        ON rw.current_node = t.sender_id
       AND t.transfer_ts > rw.last_ts                              -- chronological
       AND t.transfer_ts <= rw.ring_start_ts + INTERVAL '24' HOUR  -- time window
    WHERE rw.depth < 3   -- stop at depth 3 (prevents infinite recursion)
)

SELECT
    ring_origin                           AS user_a,
    -- Extract intermediate nodes from path
    CAST(SUBSTRING(path FROM POSITION('→' IN path) + 1
         FOR POSITION('→' IN SUBSTRING(path FROM POSITION('→' IN path) + 1)) - 1)
         AS INT)                          AS user_b,
    current_node                          AS user_c_returns_to_a,
    total_amount                          AS total_circulated,
    ring_start_ts,
    last_ts                               AS ring_end_ts,
    path || '→' || CAST(current_node AS VARCHAR(20)) AS full_path
FROM ring_walk
WHERE depth = 3
  AND current_node = ring_origin          -- the ring closes
ORDER BY ring_start_ts;
```

### Why This Is Better

| Aspect | Brute Force (Triple Join) | Recursive CTE |
|--------|--------------------------|---------------|
| **Complexity** | O(n³) worst case — every triple is evaluated | Prunes dead-ends at each depth; only viable paths survive |
| **Generalizability** | Must add more joins for rings of length 4, 5, … | Change `depth < 3` to `depth < k` for any ring length |
| **Readability** | Manageable for 3-node rings, but quickly becomes unwieldy | Single pattern; the recursion is self-documenting |
| **Early Termination** | No — all combinations must be joined first | Yes — the 24-hour and chronological filters eliminate paths at each level |

> [!TIP]
> In production, add an **index on `(sender_id, transfer_ts)`** to speed up the join in the recursive step. Partitioning the transfers table by date also helps limit the scan range.

---

## Interviewer Follow-Up Questions

1. **"How would you extend this to detect rings of arbitrary length (e.g., 4-node, 5-node rings)?"**
   - With the recursive CTE, simply increase the `depth < 3` limit. For the brute force approach, you'd need an additional self-join per hop, which is impractical. Discuss trade-offs of maximum depth vs. query time, and the need for cycle-detection logic (tracking visited nodes in the path) to avoid infinite loops.

2. **"The transfers table has 500 million rows. How do you make this performant?"**
   - Pre-filter by time window and suspicious amount ranges. Use indexed materialized views on `(sender_id, transfer_ts)`. Partition by date. Consider running the graph analysis in a streaming framework (e.g., Spark GraphFrames, Apache Flink) or a graph database (Neo4j) for truly large-scale detection. In SQL, batch processing by day/hour partitions is practical.

3. **"How would you score the 'suspiciousness' of a detected ring?"**
   - Factors: how close the amounts are across legs (low variance = more suspicious), the time between legs (faster = more suspicious), whether the same users form rings repeatedly, whether the users are newly created accounts, and the absolute dollar amount.

---

## Key Takeaways

- **Graph problems in SQL** are solved by either **self-joins** (fixed depth) or **recursive CTEs** (variable depth). Know both patterns.
- **Cycle detection** in SQL requires tracking visited nodes (via a path string or array) to avoid infinite recursion.
- **Canonical ordering** (`user_a < user_b`) or path normalization prevents reporting the same ring multiple times from different starting nodes.
- **Time-windowed constraints** are critical in fraud detection — always pair graph traversal with temporal bounds to keep the search space manageable.
- **Indexing strategy** matters enormously: `(sender_id, transfer_ts)` composite indexes are the key enabler for performant graph walks in SQL.
- Real-world fraud detection typically combines SQL-based ring detection with **scoring models** and **graph databases** for production-scale pipelines.
