# Consecutive Days Active / Streak Analysis

> Gaps & Islands Interview Variant

**Difficulty:** Medium

**Companies:** Snapchat, Meta, Spotify, LinkedIn

---

## Problem Statement

You are working on the engagement team at a social media company. The product team wants to award badges to users who maintain activity streaks — for example, a user who logs in for 7 consecutive days earns a "Weekly Warrior" badge. Given a table of daily user login events, find every consecutive-day streak for each user: the start date, end date, and length of each streak. Additionally, report each user's **longest streak**. This pattern — known as **Gaps & Islands** — appears frequently in data engineering for detecting contiguous sequences in time-series data, session analysis, and SLA compliance monitoring.

---

## Schema DDL

```sql
CREATE TABLE user_logins (
    user_id    INT  NOT NULL,
    login_date DATE NOT NULL
);

-- Sample data (18 rows, 3 users with various streak patterns)
INSERT INTO user_logins (user_id, login_date) VALUES
(1, '2024-03-01'),
(1, '2024-03-02'),
(1, '2024-03-03'),
(1, '2024-03-04'),
(1, '2024-03-06'),
(1, '2024-03-07'),
(1, '2024-03-10'),
(2, '2024-03-01'),
(2, '2024-03-02'),
(2, '2024-03-03'),
(2, '2024-03-05'),
(2, '2024-03-06'),
(2, '2024-03-07'),
(2, '2024-03-08'),
(2, '2024-03-09'),
(3, '2024-03-10'),
(3, '2024-03-11'),
(3, '2024-03-15');
```

---

## Sample Input

**user_logins**

| user_id | login_date |
|---------|------------|
| 1       | 2024-03-01 |
| 1       | 2024-03-02 |
| 1       | 2024-03-03 |
| 1       | 2024-03-04 |
| 1       | 2024-03-06 |
| 1       | 2024-03-07 |
| 1       | 2024-03-10 |
| 2       | 2024-03-01 |
| 2       | 2024-03-02 |
| 2       | 2024-03-03 |
| 2       | 2024-03-05 |
| 2       | 2024-03-06 |
| 2       | 2024-03-07 |
| 2       | 2024-03-08 |
| 2       | 2024-03-09 |
| 3       | 2024-03-10 |
| 3       | 2024-03-11 |
| 3       | 2024-03-15 |

---

## Expected Output

**All Streaks**

| user_id | streak_start | streak_end | streak_length |
|---------|-------------|------------|---------------|
| 1       | 2024-03-01  | 2024-03-04 | 4             |
| 1       | 2024-03-06  | 2024-03-07 | 2             |
| 1       | 2024-03-10  | 2024-03-10 | 1             |
| 2       | 2024-03-01  | 2024-03-03 | 3             |
| 2       | 2024-03-05  | 2024-03-09 | 5             |
| 3       | 2024-03-10  | 2024-03-11 | 2             |
| 3       | 2024-03-15  | 2024-03-15 | 1             |

**Longest Streak per User**

| user_id | longest_streak_start | longest_streak_end | longest_streak_length |
|---------|---------------------|--------------------|-----------------------|
| 1       | 2024-03-01           | 2024-03-04          | 4                     |
| 2       | 2024-03-05           | 2024-03-09          | 5                     |
| 3       | 2024-03-10           | 2024-03-11          | 2                     |

---

## Brute Force Solution

```sql
-- Approach: Use LAG to detect gaps, then assign streak IDs with a running SUM.

-- Step 1: Remove duplicate logins on the same day
WITH distinct_logins AS (
    SELECT DISTINCT user_id, login_date
    FROM user_logins
),

-- Step 2: Flag the start of a new streak
gap_flags AS (
    SELECT
        user_id,
        login_date,
        CASE
            WHEN login_date - LAG(login_date) OVER (
                     PARTITION BY user_id ORDER BY login_date
                 ) = 1
            THEN 0    -- continuation of current streak
            ELSE 1    -- new streak begins
        END AS new_streak_flag
    FROM distinct_logins
),

-- Step 3: Assign a streak ID using a running sum of the flags
streak_ids AS (
    SELECT
        user_id,
        login_date,
        SUM(new_streak_flag) OVER (
            PARTITION BY user_id ORDER BY login_date
            ROWS UNBOUNDED PRECEDING
        ) AS streak_id
    FROM gap_flags
),

-- Step 4: Aggregate each streak
streaks AS (
    SELECT
        user_id,
        MIN(login_date) AS streak_start,
        MAX(login_date) AS streak_end,
        COUNT(*)        AS streak_length
    FROM streak_ids
    GROUP BY user_id, streak_id
)
SELECT user_id, streak_start, streak_end, streak_length
FROM streaks
ORDER BY user_id, streak_start;

-- Longest Streak per User (from the same `streaks` CTE):
-- SELECT user_id,
--        streak_start  AS longest_streak_start,
--        streak_end    AS longest_streak_end,
--        streak_length AS longest_streak_length
-- FROM (
--     SELECT *,
--            ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY streak_length DESC, streak_start ASC) AS rn
--     FROM streaks
-- ) ranked
-- WHERE rn = 1
-- ORDER BY user_id;
```

### Explanation

1. **distinct_logins** — Eliminates potential duplicate rows (a user logging in twice on the same day).
2. **gap_flags** — Uses `LAG` to compare each login_date to the previous one. If the difference is exactly 1 day the streak continues (flag = 0); otherwise a new streak starts (flag = 1). The first row per user gets flag = 1 since LAG returns NULL.
3. **streak_ids** — A running SUM of the flags produces a unique streak identifier per user. Every time the flag flips to 1, the sum increments, creating a new group.
4. **Final aggregation** — Groups by `(user_id, streak_id)` to find each streak's start, end, and length.

**Note:** This approach is already quite efficient — the LAG + running SUM technique is the standard Gaps & Islands solution. The "brute force" label here is relative; a truly naive approach would use correlated subqueries.

---

## Optimal Solution

```sql
-- Approach: date-minus-row_number trick.
-- If a user is active on consecutive days, (login_date - ROW_NUMBER) is constant.

WITH distinct_logins AS (
    SELECT DISTINCT user_id, login_date
    FROM user_logins
),

grouped AS (
    SELECT
        user_id,
        login_date,
        -- Subtract a dense sequence number from the date.
        -- For consecutive dates, this produces the same "group_date".
        login_date - CAST(
            ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date)
            AS INT
        ) * INTERVAL '1' DAY AS group_key
    FROM distinct_logins
),

streaks AS (
    SELECT
        user_id,
        MIN(login_date)  AS streak_start,
        MAX(login_date)  AS streak_end,
        COUNT(*)         AS streak_length
    FROM grouped
    GROUP BY user_id, group_key
)
-- All Streaks
SELECT
    user_id,
    streak_start,
    streak_end,
    streak_length
FROM streaks
ORDER BY user_id, streak_start;

-- Longest Streak per User (from the same `streaks` CTE):
-- SELECT
--     user_id,
--     streak_start  AS longest_streak_start,
--     streak_end    AS longest_streak_end,
--     streak_length AS longest_streak_length
-- FROM (
--     SELECT
--         user_id,
--         streak_start,
--         streak_end,
--         streak_length,
--         ROW_NUMBER() OVER (
--             PARTITION BY user_id
--             ORDER BY streak_length DESC, streak_start ASC
--         ) AS rn
--     FROM streaks
-- ) t
-- WHERE rn = 1
-- ORDER BY user_id;
```

### Why This Is Better

| Aspect | LAG + Running SUM | Date Minus ROW_NUMBER |
|--------|-------------------|----------------------|
| **Window functions** | Two passes (LAG, then SUM) | One pass (ROW_NUMBER) |
| **Simplicity** | Three CTEs + CASE logic | Two CTEs, pure arithmetic |
| **Performance** | Two sorts over the partition | One sort over the partition |
| **Readability** | Requires understanding cumulative flag logic | Intuitive: "constant difference = same island" |

The **date-minus-row_number** trick works because `ROW_NUMBER()` increments by 1 for each row, and consecutive dates also increment by 1. Subtracting one from the other yields a constant for each island of consecutive dates. This constant becomes the `GROUP BY` key, collapsing each streak into a single row in one aggregation step.

> [!TIP]
> This trick requires the dates to be unique per user. Always deduplicate first, or use `DENSE_RANK` instead of `ROW_NUMBER` if duplicates are possible but you want to preserve them.

---

## Interviewer Follow-Up Questions

1. **"What if the definition of 'consecutive' is weekdays only (skip weekends)?"**
   Replace calendar-day arithmetic with business-day arithmetic. One approach: join to a calendar/date-dimension table that assigns a sequential business-day number, then apply the same ROW_NUMBER subtraction trick on that number instead of on the raw date.

2. **"How would you find users whose current streak is still active (i.e., includes today)?"**
   Add a filter after computing streaks: `WHERE streak_end = CURRENT_DATE`. Alternatively, use `MAX(login_date) OVER (PARTITION BY user_id)` inside the CTE and filter to streaks where the last date equals today.

3. **"Can you handle a tolerance — e.g., a user can miss 1 day and still keep their streak?"**
   Change the gap threshold from 1 to 2 in the LAG-based approach: flag a new streak only when `login_date - LAG(login_date) > 2`. The ROW_NUMBER trick does not directly support tolerance; the LAG + running SUM approach is more flexible here.

---

## Key Takeaways

- **Gaps & Islands** is one of the most commonly asked SQL patterns. It appears in streak detection, session analysis, status tracking, and SLA monitoring.
- The **date-minus-row_number** trick is the most elegant solution when the "step size" between consecutive rows is exactly 1 (one day, one integer ID, etc.).
- The **LAG + cumulative SUM** approach is more flexible — it supports custom gap thresholds, tolerance windows, and non-uniform step sizes.
- Always **deduplicate** before applying either technique, since duplicate dates break the ROW_NUMBER arithmetic.
- In interviews, clearly state your **definition of "consecutive"** and confirm edge cases: Does a single-day login count as a streak of length 1? What about timezone boundaries?
- This pattern maps directly to real systems: Snapchat Streaks, Duolingo daily goals, GitHub contribution graphs, and fitness app challenges.
