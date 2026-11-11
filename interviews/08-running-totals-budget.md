# 08 — Running Total with Budget Cap / Cumulative Sum Until Threshold

## Difficulty

**Medium**

## Companies

Netflix · Uber · Lyft · DoorDash

---

## Problem Statement

You are a data analyst at a ride-sharing company. Each month, the marketing team allocates a fixed **promotional budget** to reimburse riders for completed trips, processing them in chronological order. Once the cumulative reimbursement reaches the budget cap, no further trips are funded that month.

Given a table of completed trips and a monthly budget of **$500.00**, write a query that computes the **running total** of trip costs in chronological order and returns only the trips that are **fully covered** by the budget (i.e., the running total does not exceed $500). Also include the **first trip that would breach the cap** (partially funded) with the remaining budget amount.

---

## Schema DDL

```sql
CREATE TABLE trips (
    trip_id       INT PRIMARY KEY,
    rider_id      INT NOT NULL,
    trip_date     DATE NOT NULL,
    trip_cost     DECIMAL(8,2) NOT NULL,
    city          VARCHAR(30) NOT NULL
);

INSERT INTO trips (trip_id, rider_id, trip_date, trip_cost, city) VALUES
(1,  201, '2024-07-01', 45.00,  'San Francisco'),
(2,  202, '2024-07-02', 32.50,  'New York'),
(3,  203, '2024-07-03', 78.00,  'Chicago'),
(4,  204, '2024-07-04', 15.75,  'San Francisco'),
(5,  205, '2024-07-05', 120.00, 'New York'),
(6,  206, '2024-07-06', 55.00,  'Chicago'),
(7,  207, '2024-07-07', 88.25,  'San Francisco'),
(8,  208, '2024-07-08', 42.00,  'New York'),
(9,  209, '2024-07-09', 67.50,  'Chicago'),
(10, 210, '2024-07-10', 95.00,  'San Francisco'),
(11, 211, '2024-07-11', 28.00,  'New York'),
(12, 212, '2024-07-12', 110.00, 'Chicago'),
(13, 213, '2024-07-13', 73.50,  'San Francisco'),
(14, 214, '2024-07-14', 19.99,  'New York'),
(15, 215, '2024-07-15', 150.00, 'Chicago');
```

---

## Sample Input

### trips

| trip_id | rider_id | trip_date  | trip_cost | city          |
|---------|----------|------------|-----------|---------------|
| 1       | 201      | 2024-07-01 | 45.00     | San Francisco |
| 2       | 202      | 2024-07-02 | 32.50     | New York      |
| 3       | 203      | 2024-07-03 | 78.00     | Chicago       |
| 4       | 204      | 2024-07-04 | 15.75     | San Francisco |
| 5       | 205      | 2024-07-05 | 120.00    | New York      |
| 6       | 206      | 2024-07-06 | 55.00     | Chicago       |
| 7       | 207      | 2024-07-07 | 88.25     | San Francisco |
| 8       | 208      | 2024-07-08 | 42.00     | New York      |
| 9       | 209      | 2024-07-09 | 67.50     | Chicago       |
| 10      | 210      | 2024-07-10 | 95.00     | San Francisco |
| 11      | 211      | 2024-07-11 | 28.00     | New York      |
| 12      | 212      | 2024-07-12 | 110.00    | Chicago       |
| 13      | 213      | 2024-07-13 | 73.50     | San Francisco |
| 14      | 214      | 2024-07-14 | 19.99     | New York      |
| 15      | 215      | 2024-07-15 | 150.00    | Chicago       |

---

## Expected Output

Budget = **$500.00**

| trip_id | rider_id | trip_date  | trip_cost | running_total | reimbursed_amount | status         |
|---------|----------|------------|-----------|---------------|-------------------|----------------|
| 1       | 201      | 2024-07-01 | 45.00     | 45.00         | 45.00             | fully_covered  |
| 2       | 202      | 2024-07-02 | 32.50     | 77.50         | 32.50             | fully_covered  |
| 3       | 203      | 2024-07-03 | 78.00     | 155.50        | 78.00             | fully_covered  |
| 4       | 204      | 2024-07-04 | 15.75     | 171.25        | 15.75             | fully_covered  |
| 5       | 205      | 2024-07-05 | 120.00    | 291.25        | 120.00            | fully_covered  |
| 6       | 206      | 2024-07-06 | 55.00     | 346.25        | 55.00             | fully_covered  |
| 7       | 207      | 2024-07-07 | 88.25     | 434.50        | 88.25             | fully_covered  |
| 8       | 208      | 2024-07-08 | 42.00     | 476.50        | 42.00             | fully_covered  |
| 9       | 209      | 2024-07-09 | 67.50     | 544.00        | 23.50             | partial        |

---

## Brute Force Solution

Use a **correlated subquery** to compute the running total for each row, then filter.

```sql
-- Brute Force: Correlated Subquery for Running Total
WITH running AS (
    SELECT
        t.trip_id,
        t.rider_id,
        t.trip_date,
        t.trip_cost,
        (
            SELECT SUM(t2.trip_cost)
            FROM trips t2
            WHERE t2.trip_date <= t.trip_date
              AND t2.trip_id   <= t.trip_id    -- tie-break on trip_id
        ) AS running_total
    FROM trips t
)

SELECT
    r.trip_id,
    r.rider_id,
    r.trip_date,
    r.trip_cost,
    r.running_total,
    CASE
        WHEN r.running_total <= 500.00 THEN r.trip_cost
        ELSE GREATEST(0, 500.00 - (r.running_total - r.trip_cost))
    END AS reimbursed_amount,
    CASE
        WHEN r.running_total <= 500.00 THEN 'fully_covered'
        WHEN r.running_total - r.trip_cost < 500.00 THEN 'partial'
        ELSE 'not_covered'
    END AS status
FROM running r
WHERE r.running_total - r.trip_cost < 500.00   -- include up to the first breach
ORDER BY r.trip_date, r.trip_id;
```

### Step-by-Step Explanation

1. **Correlated subquery**: For each trip, sum all trip costs where the date (and trip_id for tie-breaking) is ≤ the current row — this gives the running total.
2. **Reimbursement logic**: If the running total ≤ budget, the full trip cost is reimbursed. If the running total exceeds the budget but the *previous* running total was below, compute the partial amount (`budget - previous_running_total`).
3. **Filter**: Keep rows where `running_total - trip_cost < budget` (i.e., the running total *before* this trip was still under budget).

> **Drawback**: The correlated subquery runs O(n) work per row, making the overall complexity **O(n²)**. On a table with millions of trips, this is prohibitively slow.

---

## Optimal Solution

Use a **window function** (`SUM() OVER`) for the running total — this is computed in a single pass over the sorted data.

```sql
-- Optimal: Window Function with Budget Cap Logic
WITH ranked_trips AS (
    SELECT
        trip_id,
        rider_id,
        trip_date,
        trip_cost,
        SUM(trip_cost) OVER (
            ORDER BY trip_date, trip_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_total
    FROM trips
),

budget_applied AS (
    SELECT
        trip_id,
        rider_id,
        trip_date,
        trip_cost,
        running_total,
        running_total - trip_cost AS prev_running_total,
        CASE
            WHEN running_total <= 500.00 THEN trip_cost
            WHEN running_total - trip_cost < 500.00
                THEN 500.00 - (running_total - trip_cost)
            ELSE 0
        END AS reimbursed_amount,
        CASE
            WHEN running_total <= 500.00 THEN 'fully_covered'
            WHEN running_total - trip_cost < 500.00 THEN 'partial'
            ELSE 'not_covered'
        END AS status
    FROM ranked_trips
)

SELECT
    trip_id,
    rider_id,
    trip_date,
    trip_cost,
    running_total,
    reimbursed_amount,
    status
FROM budget_applied
WHERE status IN ('fully_covered', 'partial')
ORDER BY trip_date, trip_id;
```

### Why This Is Better

| Aspect | Correlated Subquery | Window Function |
|--------|---------------------|-----------------|
| **Time complexity** | O(n²) — rescans for each row | O(n log n) for sort + O(n) for scan = **O(n log n)** |
| **Readability** | Nested subquery is hard to follow | Declarative `SUM() OVER(...)` is immediately clear |
| **Optimizer support** | Limited; hard to parallelize | Window functions are highly optimized in all modern engines |
| **Extensibility** | Adding per-city budgets requires restructuring | Add `PARTITION BY city` to the window frame |

> [!TIP]
> The `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` frame is the **default** for `SUM() OVER(ORDER BY ...)` in most engines, but always specify it explicitly for clarity and to avoid subtle `RANGE` vs `ROWS` differences when there are ties in the `ORDER BY` column.

---

## Interviewer Follow-Up Questions

1. **"How would you handle per-city budgets instead of a single global budget?"**
   - Add `PARTITION BY city` to the window function: `SUM(trip_cost) OVER (PARTITION BY city ORDER BY trip_date, trip_id ...)`. Then join a `city_budgets` table to compare each city's running total against its allocated budget. The same `CASE` logic applies per partition.

2. **"What if trips can have the same date and you need deterministic ordering?"**
   - Always include a unique tiebreaker in the `ORDER BY` clause (e.g., `trip_id` or `created_at` timestamp). Without a tiebreaker, `ROWS` and `RANGE` frames behave differently: `RANGE` treats ties as a group, while `ROWS` picks an arbitrary order among ties.

3. **"How would you carry this budget cap forward across months in a pipeline?"**
   - Store monthly budgets in a dimension table. Partition the window by `(year, month)`. In an incremental pipeline, track the `remaining_budget` per month as state, and new trips are evaluated against it. This is a classic **stateful streaming** pattern in tools like Apache Flink or Spark Structured Streaming.

---

## Key Takeaways

- **`SUM() OVER (ORDER BY ... ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)`** is the canonical way to compute a running total in SQL.
- Always prefer **window functions** over correlated subqueries for cumulative computations — O(n log n) vs O(n²).
- The **budget cap pattern** (running total + threshold) is a two-step process: compute the running total, then apply conditional logic to classify rows as fully covered, partially covered, or not covered.
- **`ROWS` vs `RANGE`** matters when there are ties in the `ORDER BY` column. Use `ROWS` for deterministic row-by-row accumulation; use `RANGE` only when you intentionally want to group tied values together.
- Always include a **tiebreaker column** (like a primary key) in the `ORDER BY` of a window function to ensure deterministic results.
- This pattern extends naturally to **per-group budgets** via `PARTITION BY`.
