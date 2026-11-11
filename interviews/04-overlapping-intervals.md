# Detecting Overlapping Bookings / Resource Contention

> Overlapping Date Ranges & Interval Merging

**Difficulty:** Hard

**Companies:** Airbnb, Google, Uber, Booking.com

---

## Problem Statement

You are a backend engineer at a vacation rental platform. The trust & safety team has discovered that some properties have **overlapping bookings** — two or more reservations that claim the same property for overlapping date ranges. This causes double-booking disputes and guest complaints. Given a table of bookings with check-in and check-out dates, write a query that (1) identifies all pairs of overlapping bookings for the same property, and (2) merges overlapping intervals into consolidated "occupied" periods per property. This problem tests your ability to reason about interval overlap conditions, self-joins, and the classic **interval merging** algorithm using window functions.

---

## Schema DDL

```sql
CREATE TABLE properties (
    property_id   INT          NOT NULL PRIMARY KEY,
    property_name VARCHAR(100) NOT NULL,
    city          VARCHAR(50)  NOT NULL
);

CREATE TABLE bookings (
    booking_id   INT  NOT NULL PRIMARY KEY,
    property_id  INT  NOT NULL,
    guest_name   VARCHAR(100) NOT NULL,
    check_in     DATE NOT NULL,
    check_out    DATE NOT NULL   -- exclusive: guest leaves on this day
);

-- Properties
INSERT INTO properties (property_id, property_name, city) VALUES
(101, 'Beachfront Villa',  'Miami'),
(102, 'Downtown Loft',     'NYC'),
(103, 'Mountain Cabin',    'Denver');

-- Bookings (15 rows — several overlapping pairs)
INSERT INTO bookings (booking_id, property_id, guest_name, check_in, check_out) VALUES
(1,  101, 'Alice',   '2024-06-01', '2024-06-05'),
(2,  101, 'Bob',     '2024-06-04', '2024-06-08'),
(3,  101, 'Charlie', '2024-06-10', '2024-06-14'),
(4,  101, 'Diana',   '2024-06-13', '2024-06-17'),
(5,  101, 'Eve',     '2024-06-20', '2024-06-23'),
(6,  102, 'Frank',   '2024-06-01', '2024-06-07'),
(7,  102, 'Grace',   '2024-06-05', '2024-06-10'),
(8,  102, 'Hank',    '2024-06-09', '2024-06-12'),
(9,  102, 'Ivy',     '2024-06-15', '2024-06-18'),
(10, 102, 'Jack',    '2024-06-15', '2024-06-18'),
(11, 103, 'Karen',   '2024-07-01', '2024-07-05'),
(12, 103, 'Leo',     '2024-07-06', '2024-07-10'),
(13, 103, 'Mia',     '2024-07-03', '2024-07-07'),
(14, 103, 'Noah',    '2024-07-12', '2024-07-15'),
(15, 103, 'Olivia',  '2024-07-14', '2024-07-18');
```

---

## Sample Input

**properties**

| property_id | property_name    | city   |
|-------------|------------------|--------|
| 101         | Beachfront Villa | Miami  |
| 102         | Downtown Loft    | NYC    |
| 103         | Mountain Cabin   | Denver |

**bookings**

| booking_id | property_id | guest_name | check_in   | check_out  |
|------------|-------------|------------|------------|------------|
| 1          | 101         | Alice      | 2024-06-01 | 2024-06-05 |
| 2          | 101         | Bob        | 2024-06-04 | 2024-06-08 |
| 3          | 101         | Charlie    | 2024-06-10 | 2024-06-14 |
| 4          | 101         | Diana      | 2024-06-13 | 2024-06-17 |
| 5          | 101         | Eve        | 2024-06-20 | 2024-06-23 |
| 6          | 102         | Frank      | 2024-06-01 | 2024-06-07 |
| 7          | 102         | Grace      | 2024-06-05 | 2024-06-10 |
| 8          | 102         | Hank       | 2024-06-09 | 2024-06-12 |
| 9          | 102         | Ivy        | 2024-06-15 | 2024-06-18 |
| 10         | 102         | Jack       | 2024-06-15 | 2024-06-18 |
| 11         | 103         | Karen      | 2024-07-01 | 2024-07-05 |
| 12         | 103         | Leo        | 2024-07-06 | 2024-07-10 |
| 13         | 103         | Mia        | 2024-07-03 | 2024-07-07 |
| 14         | 103         | Noah       | 2024-07-12 | 2024-07-15 |
| 15         | 103         | Olivia     | 2024-07-14 | 2024-07-18 |

---

## Expected Output

### Part 1: Overlapping Booking Pairs

| property_id | booking_a | guest_a  | booking_b | guest_b  | overlap_start | overlap_end |
|-------------|-----------|----------|-----------|----------|---------------|-------------|
| 101         | 1         | Alice    | 2         | Bob      | 2024-06-04    | 2024-06-05  |
| 101         | 3         | Charlie  | 4         | Diana    | 2024-06-13    | 2024-06-14  |
| 102         | 6         | Frank    | 7         | Grace    | 2024-06-05    | 2024-06-07  |
| 102         | 7         | Grace    | 8         | Hank     | 2024-06-09    | 2024-06-10  |
| 102         | 9         | Ivy      | 10        | Jack     | 2024-06-15    | 2024-06-18  |
| 103         | 11        | Karen    | 13        | Mia      | 2024-07-03    | 2024-07-05  |
| 103         | 12        | Leo      | 13        | Mia      | 2024-07-06    | 2024-07-07  |
| 103         | 14        | Noah     | 15        | Olivia   | 2024-07-14    | 2024-07-15  |

### Part 2: Merged Occupied Periods per Property

| property_id | occupied_start | occupied_end |
|-------------|----------------|--------------|
| 101         | 2024-06-01     | 2024-06-08   |
| 101         | 2024-06-10     | 2024-06-17   |
| 101         | 2024-06-20     | 2024-06-23   |
| 102         | 2024-06-01     | 2024-06-12   |
| 102         | 2024-06-15     | 2024-06-18   |
| 103         | 2024-07-01     | 2024-07-10   |
| 103         | 2024-07-12     | 2024-07-18   |

---

## Brute Force Solution

### Part 1: Find Overlapping Pairs (Self-Join)

```sql
-- Two intervals [a_start, a_end) and [b_start, b_end) overlap
-- if and only if: a_start < b_end AND b_start < a_end

SELECT
    a.property_id,
    a.booking_id   AS booking_a,
    a.guest_name   AS guest_a,
    b.booking_id   AS booking_b,
    b.guest_name   AS guest_b,
    -- The overlap region
    CASE WHEN a.check_in  > b.check_in  THEN a.check_in  ELSE b.check_in  END AS overlap_start,
    CASE WHEN a.check_out < b.check_out THEN a.check_out ELSE b.check_out END AS overlap_end
FROM bookings a
JOIN bookings b
    ON  a.property_id = b.property_id
    AND a.booking_id  < b.booking_id        -- avoid duplicates & self-pairs
    AND a.check_in    < b.check_out          -- overlap condition
    AND b.check_in    < a.check_out          -- overlap condition
ORDER BY a.property_id, a.booking_id, b.booking_id;
```

### Part 2: Merge Intervals (Brute Force — Correlated Subquery)

```sql
-- For each booking, check if any earlier booking on the same property
-- "covers" it (i.e., has an overlapping or adjacent range). If not,
-- it starts a new merged interval.

WITH ordered_bookings AS (
    SELECT
        property_id,
        check_in,
        check_out,
        ROW_NUMBER() OVER (PARTITION BY property_id ORDER BY check_in, check_out) AS rn
    FROM bookings
),

-- Mark a booking as starting a new group if no prior booking's check_out >= this check_in
new_group_flags AS (
    SELECT
        ob.*,
        CASE
            WHEN NOT EXISTS (
                SELECT 1
                FROM ordered_bookings ob2
                WHERE ob2.property_id = ob.property_id
                  AND ob2.rn < ob.rn
                  AND ob2.check_out >= ob.check_in
            ) THEN 1
            ELSE 0
        END AS is_new_group
    FROM ordered_bookings ob
),

group_ids AS (
    SELECT
        property_id,
        check_in,
        check_out,
        SUM(is_new_group) OVER (
            PARTITION BY property_id ORDER BY check_in, check_out
            ROWS UNBOUNDED PRECEDING
        ) AS grp
    FROM new_group_flags
)

SELECT
    property_id,
    MIN(check_in)  AS occupied_start,
    MAX(check_out)  AS occupied_end
FROM group_ids
GROUP BY property_id, grp
ORDER BY property_id, occupied_start;
```

### Explanation

1. **Overlap detection** uses the standard interval overlap condition: `A.start < B.end AND B.start < A.end`. The `a.booking_id < b.booking_id` condition avoids counting each pair twice and eliminates self-joins.
2. **Interval merging** (brute force) uses a correlated `NOT EXISTS` to check whether any *prior* booking extends into the current one's range. If not, the current booking begins a new merged group. A running SUM of these flags assigns group IDs.

**Drawback:** The correlated `NOT EXISTS` subquery is O(n²) per property, which becomes prohibitive with thousands of bookings per property.

---

## Optimal Solution

### Part 1: Overlapping Pairs (same as brute force — self-join is the standard approach)

```sql
SELECT
    a.property_id,
    a.booking_id   AS booking_a,
    a.guest_name   AS guest_a,
    b.booking_id   AS booking_b,
    b.guest_name   AS guest_b,
    GREATEST(a.check_in, b.check_in)   AS overlap_start,
    LEAST(a.check_out, b.check_out)    AS overlap_end
FROM bookings a
JOIN bookings b
    ON  a.property_id = b.property_id
    AND a.booking_id  < b.booking_id
    AND a.check_in    < b.check_out
    AND b.check_in    < a.check_out
ORDER BY a.property_id, a.booking_id;
```

### Part 2: Merge Intervals (Running MAX approach)

```sql
WITH with_running_max AS (
    SELECT
        property_id,
        check_in,
        check_out,
        -- Track the farthest check_out seen so far (before this row)
        MAX(check_out) OVER (
            PARTITION BY property_id
            ORDER BY check_in, check_out
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_max_checkout
    FROM bookings
),

new_group_flags AS (
    SELECT
        property_id,
        check_in,
        check_out,
        -- A new group starts when this booking's check_in is at or after the previous max check_out
        -- (or it is the first booking for this property)
        CASE
            WHEN prev_max_checkout IS NULL        THEN 1  -- first booking
            WHEN check_in >= prev_max_checkout     THEN 1  -- gap detected
            ELSE 0
        END AS is_new_group
    FROM with_running_max
),

group_ids AS (
    SELECT
        property_id,
        check_in,
        check_out,
        SUM(is_new_group) OVER (
            PARTITION BY property_id
            ORDER BY check_in, check_out
            ROWS UNBOUNDED PRECEDING
        ) AS grp
    FROM new_group_flags
)

SELECT
    property_id,
    MIN(check_in)  AS occupied_start,
    MAX(check_out) AS occupied_end
FROM group_ids
GROUP BY property_id, grp
ORDER BY property_id, occupied_start;
```

### Why This Is Better

| Aspect | Brute Force (Correlated Subquery) | Optimal (Running MAX) |
|--------|-----------------------------------|----------------------|
| **Complexity** | O(n²) per property (subquery per row) | O(n log n) per property (single sort + single scan) |
| **Scans** | Rescans all prior rows for every row | Single pass with a running maximum |
| **Readability** | Nested `NOT EXISTS` logic | Declarative window frame — easy to audit |
| **Engine support** | Works everywhere but slowly | `ROWS BETWEEN ... AND 1 PRECEDING` supported by all modern engines |

**The key insight:** After sorting by `check_in`, a new merged interval starts only when the current `check_in ≥ MAX(check_out)` of all preceding rows. The running MAX replaces the correlated subquery entirely.

> [!IMPORTANT]
> The overlap condition assumes **half-open intervals** `[check_in, check_out)` — the guest checks out on `check_out` day and the next guest can check in on the same day. Always clarify with the interviewer whether the boundary is inclusive or exclusive.

---

## Interviewer Follow-Up Questions

1. **"What if a single booking can overlap with many others (chain of overlaps)? How does your merge handle transitive overlaps?"**
   The running-MAX approach handles transitive overlaps naturally. If booking A overlaps B, and B overlaps C, the running max from A carries forward through B and keeps C in the same group — even if A and C don't directly overlap. This is because `MAX(check_out)` accumulates the farthest endpoint seen, absorbing every chained overlap.

2. **"How would you find the maximum number of concurrent bookings at any point in time (max resource contention)?"**
   Use an **event-based sweep line**: create +1 events for each check_in and -1 events for each check_out, union them, sort by date, compute a running SUM, and take the MAX. This gives the peak concurrent bookings for each property.

   ```sql
   WITH events AS (
       SELECT property_id, check_in  AS event_date,  1 AS delta FROM bookings
       UNION ALL
       SELECT property_id, check_out AS event_date, -1 AS delta FROM bookings
   )
   SELECT property_id, MAX(concurrent) AS peak_concurrent
   FROM (
       SELECT property_id, event_date,
              SUM(delta) OVER (PARTITION BY property_id ORDER BY event_date) AS concurrent
       FROM events
   ) t
   GROUP BY property_id;
   ```

3. **"How does this change if you need to prevent overlaps at write time, not just detect them?"**
   At the application/database level, use a combination of:
   - **Exclusion constraints** (PostgreSQL `EXCLUDE USING gist` with `tsrange`).
   - **Serializable isolation** or `SELECT ... FOR UPDATE` with a range-overlap check before inserting.
   - **Materialized availability slots** — pre-compute open date ranges and only allow bookings that fit within an open slot.

---

## Key Takeaways

- **Interval overlap condition**: Two intervals `[A_start, A_end)` and `[B_start, B_end)` overlap iff `A_start < B_end AND B_start < A_end`. Commit this to memory.
- **Self-join with `a.id < b.id`** is the standard way to enumerate all unique pairs without duplicates or self-matches.
- **`GREATEST` / `LEAST`** cleanly compute the overlap region (intersection) of two intervals.
- **Interval merging** uses a running MAX of the end-point over rows sorted by start-point. A new group begins whenever the current start exceeds the running max.
- **Sweep-line / event-based** approach (±1 events with a running SUM) is the go-to for counting concurrent intervals and finding peak contention.
- **Always clarify boundary semantics**: closed `[start, end]` vs. half-open `[start, end)` changes the overlap condition (`<` vs. `<=`).
