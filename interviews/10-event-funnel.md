# 10 — Multi-Step Event Funnel Analysis

## Difficulty

**Hard**

## Companies

Meta · Google · Airbnb · Uber · Spotify

---

## Problem Statement

You are a product analyst at a music streaming platform. The growth team wants to understand user conversion through the **onboarding funnel**: users land on the homepage (`page_view`), then sign up (`sign_up`), then start a free trial (`start_trial`), and finally convert to a paid subscription (`subscribe`). These events must happen **in order** for a given user, but not necessarily consecutively — there may be other events in between.

Write a query that calculates the **funnel conversion report**: for each step, show the number of users who reached that step, the **drop-off count** from the previous step, and the **conversion rate** (both step-over-step and overall from the top of the funnel). Users must complete steps in the defined order, and only the **first occurrence** of each event type per user counts.

---

## Schema DDL

```sql
CREATE TABLE events (
    event_id    BIGINT PRIMARY KEY,
    user_id     INT NOT NULL,
    event_type  VARCHAR(30) NOT NULL,
    event_ts    TIMESTAMP NOT NULL,
    platform    VARCHAR(20) NOT NULL
);

INSERT INTO events (event_id, user_id, event_type, event_ts, platform) VALUES
(1,  1001, 'page_view',   '2024-08-01 10:00:00', 'web'),
(2,  1001, 'sign_up',     '2024-08-01 10:05:00', 'web'),
(3,  1001, 'start_trial', '2024-08-01 10:10:00', 'web'),
(4,  1001, 'subscribe',   '2024-08-08 09:00:00', 'web'),
(5,  1002, 'page_view',   '2024-08-01 11:00:00', 'mobile'),
(6,  1002, 'sign_up',     '2024-08-01 11:30:00', 'mobile'),
(7,  1002, 'start_trial', '2024-08-02 08:00:00', 'mobile'),
(8,  1003, 'page_view',   '2024-08-01 12:00:00', 'web'),
(9,  1003, 'sign_up',     '2024-08-01 12:15:00', 'web'),
(10, 1004, 'page_view',   '2024-08-01 14:00:00', 'mobile'),
(11, 1005, 'page_view',   '2024-08-02 09:00:00', 'web'),
(12, 1005, 'sign_up',     '2024-08-02 09:20:00', 'web'),
(13, 1005, 'start_trial', '2024-08-02 09:25:00', 'web'),
(14, 1005, 'subscribe',   '2024-08-10 10:00:00', 'web'),
(15, 1006, 'page_view',   '2024-08-02 10:00:00', 'mobile'),
(16, 1006, 'sign_up',     '2024-08-02 10:45:00', 'mobile'),
(17, 1007, 'page_view',   '2024-08-03 08:00:00', 'web'),
(18, 1007, 'sign_up',     '2024-08-03 08:10:00', 'web'),
(19, 1007, 'start_trial', '2024-08-03 08:15:00', 'web'),
(20, 1007, 'subscribe',   '2024-08-11 07:00:00', 'web'),
(21, 1008, 'page_view',   '2024-08-03 09:00:00', 'mobile'),
(22, 1009, 'page_view',   '2024-08-03 11:00:00', 'web'),
(23, 1009, 'sign_up',     '2024-08-03 11:30:00', 'web'),
(24, 1010, 'page_view',   '2024-08-04 10:00:00', 'mobile'),
(25, 1010, 'sign_up',     '2024-08-04 10:20:00', 'mobile'),
(26, 1010, 'start_trial', '2024-08-04 10:25:00', 'mobile'),
(27, 1003, 'page_view',   '2024-08-05 09:00:00', 'web'),      -- repeat visit, ignored
(28, 1001, 'page_view',   '2024-08-06 08:00:00', 'web'),      -- repeat visit, ignored
(29, 1011, 'sign_up',     '2024-08-04 12:00:00', 'web'),      -- sign_up without page_view
(30, 1012, 'page_view',   '2024-08-05 14:00:00', 'mobile');
```

---

## Sample Input

### events

| event_id | user_id | event_type  | event_ts            | platform |
|----------|---------|-------------|---------------------|----------|
| 1        | 1001    | page_view   | 2024-08-01 10:00:00 | web      |
| 2        | 1001    | sign_up     | 2024-08-01 10:05:00 | web      |
| 3        | 1001    | start_trial | 2024-08-01 10:10:00 | web      |
| 4        | 1001    | subscribe   | 2024-08-08 09:00:00 | web      |
| 5        | 1002    | page_view   | 2024-08-01 11:00:00 | mobile   |
| 6        | 1002    | sign_up     | 2024-08-01 11:30:00 | mobile   |
| 7        | 1002    | start_trial | 2024-08-02 08:00:00 | mobile   |
| 8        | 1003    | page_view   | 2024-08-01 12:00:00 | web      |
| 9        | 1003    | sign_up     | 2024-08-01 12:15:00 | web      |
| 10       | 1004    | page_view   | 2024-08-01 14:00:00 | mobile   |
| 11       | 1005    | page_view   | 2024-08-02 09:00:00 | web      |
| 12       | 1005    | sign_up     | 2024-08-02 09:20:00 | web      |
| 13       | 1005    | start_trial | 2024-08-02 09:25:00 | web      |
| 14       | 1005    | subscribe   | 2024-08-10 10:00:00 | web      |
| 15       | 1006    | page_view   | 2024-08-02 10:00:00 | mobile   |
| 16       | 1006    | sign_up     | 2024-08-02 10:45:00 | mobile   |
| 17       | 1007    | page_view   | 2024-08-03 08:00:00 | web      |
| 18       | 1007    | sign_up     | 2024-08-03 08:10:00 | web      |
| 19       | 1007    | start_trial | 2024-08-03 08:15:00 | web      |
| 20       | 1007    | subscribe   | 2024-08-11 07:00:00 | web      |
| 21       | 1008    | page_view   | 2024-08-03 09:00:00 | mobile   |
| 22       | 1009    | page_view   | 2024-08-03 11:00:00 | web      |
| 23       | 1009    | sign_up     | 2024-08-03 11:30:00 | web      |
| 24       | 1010    | page_view   | 2024-08-04 10:00:00 | mobile   |
| 25       | 1010    | sign_up     | 2024-08-04 10:20:00 | mobile   |
| 26       | 1010    | start_trial | 2024-08-04 10:25:00 | mobile   |
| 27       | 1003    | page_view   | 2024-08-05 09:00:00 | web      |
| 28       | 1001    | page_view   | 2024-08-06 08:00:00 | web      |
| 29       | 1011    | sign_up     | 2024-08-04 12:00:00 | web      |
| 30       | 1012    | page_view   | 2024-08-05 14:00:00 | mobile   |

---

## Expected Output

| step_number | step_name   | users_reached | dropoff_count | step_conversion_rate | overall_conversion_rate |
|-------------|-------------|---------------|---------------|----------------------|-------------------------|
| 1           | page_view   | 11            | 0             | 100.0%               | 100.0%                  |
| 2           | sign_up     | 8             | 3             | 72.7%                | 72.7%                   |
| 3           | start_trial | 5             | 3             | 62.5%                | 45.5%                   |
| 4           | subscribe   | 3             | 2             | 60.0%                | 27.3%                   |

> **Note**: 11 distinct users (`1001`–`1010` and `1012`) had a `page_view`. User `1011` signed up without a `page_view`, so they are excluded from the funnel (did not enter at step 1).

---

## Brute Force Solution

Use **separate subqueries** to count users at each step, joining each step to the previous one to enforce ordering.

```sql
-- Brute Force: Separate subqueries with sequential joins

-- Step 1: Users who had a page_view
WITH step1 AS (
    SELECT DISTINCT user_id,
           MIN(event_ts) AS step1_ts
    FROM events
    WHERE event_type = 'page_view'
    GROUP BY user_id
),

-- Step 2: Users who signed up AFTER their page_view
step2 AS (
    SELECT DISTINCT s1.user_id,
           MIN(e.event_ts) AS step2_ts
    FROM step1 s1
    JOIN events e
        ON s1.user_id = e.user_id
       AND e.event_type = 'sign_up'
       AND e.event_ts > s1.step1_ts
    GROUP BY s1.user_id
),

-- Step 3: Users who started a trial AFTER their sign_up
step3 AS (
    SELECT DISTINCT s2.user_id,
           MIN(e.event_ts) AS step3_ts
    FROM step2 s2
    JOIN events e
        ON s2.user_id = e.user_id
       AND e.event_type = 'start_trial'
       AND e.event_ts > s2.step2_ts
    GROUP BY s2.user_id
),

-- Step 4: Users who subscribed AFTER their trial start
step4 AS (
    SELECT DISTINCT s3.user_id
    FROM step3 s3
    JOIN events e
        ON s3.user_id = e.user_id
       AND e.event_type = 'subscribe'
       AND e.event_ts > s3.step3_ts
),

-- Combine counts
funnel_counts AS (
    SELECT 1 AS step_number, 'page_view'   AS step_name, COUNT(*) AS users_reached FROM step1
    UNION ALL
    SELECT 2, 'sign_up',     COUNT(*) FROM step2
    UNION ALL
    SELECT 3, 'start_trial', COUNT(*) FROM step3
    UNION ALL
    SELECT 4, 'subscribe',   COUNT(*) FROM step4
)

SELECT
    step_number,
    step_name,
    users_reached,
    COALESCE(LAG(users_reached) OVER (ORDER BY step_number) - users_reached, 0) AS dropoff_count,
    CONCAT(
        ROUND(100.0 * users_reached /
              COALESCE(LAG(users_reached) OVER (ORDER BY step_number), users_reached), 1),
        '%'
    ) AS step_conversion_rate,
    CONCAT(
        ROUND(100.0 * users_reached /
              FIRST_VALUE(users_reached) OVER (ORDER BY step_number), 1),
        '%'
    ) AS overall_conversion_rate
FROM funnel_counts
ORDER BY step_number;
```

### Step-by-Step Explanation

1. **Step 1 CTE**: Find all users who had a `page_view` (the funnel entry point).
2. **Step 2 CTE**: Join step 1 users to `sign_up` events that occurred after their page view.
3. **Step 3 CTE**: Join step 2 users to `start_trial` events that occurred after their sign up.
4. **Step 4 CTE**: Join step 3 users to `subscribe` events that occurred after their trial start.
5. **funnel_counts**: Union the counts from each step.
6. **Window functions**: Compute drop-off and conversion rates.

> **Drawback**: Each step requires a separate join back to the events table — this means **4 scans** of the events table. Adding or reordering steps requires restructuring all downstream CTEs. The cascading join pattern is rigid and error-prone.

---

## Optimal Solution

Use **conditional aggregation with MIN()** to find the first timestamp of each event type per user in a single pass, then evaluate funnel progression with simple timestamp comparisons.

```sql
-- Optimal: Single-pass conditional aggregation

WITH user_first_events AS (
    -- Single scan: get each user's first timestamp per event type
    SELECT
        user_id,
        MIN(CASE WHEN event_type = 'page_view'   THEN event_ts END) AS first_page_view,
        MIN(CASE WHEN event_type = 'sign_up'     THEN event_ts END) AS first_sign_up,
        MIN(CASE WHEN event_type = 'start_trial' THEN event_ts END) AS first_start_trial,
        MIN(CASE WHEN event_type = 'subscribe'   THEN event_ts END) AS first_subscribe
    FROM events
    WHERE event_type IN ('page_view', 'sign_up', 'start_trial', 'subscribe')
    GROUP BY user_id
),

user_funnel AS (
    -- Determine how far each user progressed (with ordering enforced)
    SELECT
        user_id,
        CASE WHEN first_page_view IS NOT NULL
             THEN 1 ELSE 0 END AS reached_step1,
        CASE WHEN first_page_view IS NOT NULL
              AND first_sign_up IS NOT NULL
              AND first_sign_up > first_page_view
             THEN 1 ELSE 0 END AS reached_step2,
        CASE WHEN first_page_view IS NOT NULL
              AND first_sign_up IS NOT NULL
              AND first_start_trial IS NOT NULL
              AND first_sign_up > first_page_view
              AND first_start_trial > first_sign_up
             THEN 1 ELSE 0 END AS reached_step3,
        CASE WHEN first_page_view IS NOT NULL
              AND first_sign_up IS NOT NULL
              AND first_start_trial IS NOT NULL
              AND first_subscribe IS NOT NULL
              AND first_sign_up > first_page_view
              AND first_start_trial > first_sign_up
              AND first_subscribe > first_start_trial
             THEN 1 ELSE 0 END AS reached_step4
    FROM user_first_events
),

step_counts AS (
    SELECT 1 AS step_number, 'page_view'   AS step_name, SUM(reached_step1) AS users_reached FROM user_funnel
    UNION ALL
    SELECT 2, 'sign_up',     SUM(reached_step2) FROM user_funnel
    UNION ALL
    SELECT 3, 'start_trial', SUM(reached_step3) FROM user_funnel
    UNION ALL
    SELECT 4, 'subscribe',   SUM(reached_step4) FROM user_funnel
)

SELECT
    step_number,
    step_name,
    users_reached,
    COALESCE(
        LAG(users_reached) OVER (ORDER BY step_number) - users_reached, 0
    ) AS dropoff_count,
    CONCAT(
        ROUND(100.0 * users_reached /
              COALESCE(LAG(users_reached) OVER (ORDER BY step_number), users_reached), 1),
        '%'
    ) AS step_conversion_rate,
    CONCAT(
        ROUND(100.0 * users_reached /
              FIRST_VALUE(users_reached) OVER (ORDER BY step_number), 1),
        '%'
    ) AS overall_conversion_rate
FROM step_counts
ORDER BY step_number;
```

### Why This Is Better

| Aspect | Brute Force (Cascading Joins) | Optimal (Single-Pass Aggregation) |
|--------|-------------------------------|-----------------------------------|
| **Table scans** | 4+ scans (one join per step) | **Single scan** of the events table |
| **Complexity** | Each step depends on the prior CTE — rigid chain | Flat structure; each step evaluated independently from the same base |
| **Adding steps** | Insert a new CTE in the middle, update all downstream | Add one more `MIN(CASE WHEN ...)` column and one more CASE in `user_funnel` |
| **Performance** | O(n × k) where k = number of steps | O(n) single-pass aggregation |
| **Ordering enforcement** | Handled by join conditions (correct but verbose) | Simple timestamp comparisons (concise and auditable) |

> [!TIP]
> In BigQuery and Snowflake, consider using **`ARRAY_AGG(event_type ORDER BY event_ts)`** per user and then checking if the array contains the subsequence in order. This is even more flexible for funnels with optional or branching steps.

---

## Interviewer Follow-Up Questions

1. **"How would you segment this funnel by platform (web vs. mobile) or by acquisition cohort?"**
   - Add `platform` (or a cohort identifier) as a grouping dimension: change `GROUP BY user_id` to `GROUP BY user_id, platform` in `user_first_events`, and add it to every downstream CTE. For cohort analysis, join a `users` table with `signup_date` or `cohort_week` and partition the funnel counts by cohort.

2. **"How would you add a time constraint — e.g., the user must complete the funnel within 7 days?"**
   - Add a `WHERE` filter in `user_funnel`: `AND first_subscribe <= first_page_view + INTERVAL '7' DAY`. This ensures the entire journey is within the SLA. You can also measure **time-between-steps** by computing `first_sign_up - first_page_view`, etc., and reporting median/p90 latencies per step.

3. **"What if you want to support arbitrary funnel definitions without changing the SQL?"**
   - Store the funnel definition in a configuration table (`funnel_steps(step_number, event_type)`). Use a **recursive CTE** or **procedural SQL** to dynamically build the funnel. In dbt, use Jinja to loop over the step definitions and generate the CASE expressions. Some analytics platforms (Amplitude, Mixpanel) provide funnel analysis as a first-class feature.

---

## Key Takeaways

- **Funnel analysis in SQL** is fundamentally a **sequence-matching** problem: determine how far each user progresses through an ordered set of events.
- The **single-pass conditional aggregation** pattern (`MIN(CASE WHEN event_type = 'X' THEN event_ts END)`) is the most efficient way to extract multiple event timestamps per user in one scan.
- **Ordering is enforced by timestamp comparison**, not by join ordering — this keeps the logic flat and auditable.
- **`LAG()` and `FIRST_VALUE()`** over the step counts are the standard way to compute drop-off and overall conversion rates.
- Always use the **first occurrence** of each event type per user (`MIN(event_ts)`) to avoid double-counting repeated events.
- For production funnel pipelines, consider **materialized user-journey tables** that pre-compute the first timestamp of each event per user, updated incrementally.
- **Beware of users who skip steps** (e.g., sign_up without page_view): decide upfront whether they enter the funnel or are excluded, and document the business rule.
