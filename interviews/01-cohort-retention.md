# Active User Retention & Cohort Churn

> MOM / YOY Retention Matrices

**Difficulty:** Hard

**Companies:** Meta, Netflix, Spotify, Airbnb

---

## Problem Statement

You are a data analyst at a music streaming company. The product team wants to understand how well the platform retains users after their first sign-up month. Given a table of user activity events, compute a **monthly cohort retention matrix**: for each sign-up cohort (defined by the month a user first became active), calculate the percentage of users who return in each subsequent month (Month 0, Month 1, Month 2, …). The retention rate for Month 0 is always 100%. This analysis helps the company identify whether recent product changes have improved or worsened long-term user engagement, and it feeds directly into churn models and LTV forecasting.

---

## Schema DDL

```sql
CREATE TABLE user_activity (
    user_id       INT          NOT NULL,
    activity_date DATE         NOT NULL,
    activity_type VARCHAR(50)  NOT NULL   -- e.g. 'stream', 'search', 'like'
);

-- Sample data (15 rows covering 4 users across several months)
INSERT INTO user_activity (user_id, activity_date, activity_type) VALUES
(1, '2024-01-05', 'stream'),
(1, '2024-01-18', 'like'),
(1, '2024-02-10', 'stream'),
(1, '2024-03-02', 'stream'),
(1, '2024-05-15', 'search'),
(2, '2024-01-12', 'stream'),
(2, '2024-02-20', 'stream'),
(2, '2024-02-25', 'like'),
(3, '2024-02-01', 'stream'),
(3, '2024-02-14', 'like'),
(3, '2024-03-08', 'stream'),
(3, '2024-04-22', 'stream'),
(3, '2024-05-11', 'search'),
(4, '2024-03-03', 'stream'),
(4, '2024-03-19', 'like');
```

---

## Sample Input

**user_activity**

| user_id | activity_date | activity_type |
|---------|---------------|---------------|
| 1       | 2024-01-05    | stream        |
| 1       | 2024-01-18    | like          |
| 1       | 2024-02-10    | stream        |
| 1       | 2024-03-02    | stream        |
| 1       | 2024-05-15    | search        |
| 2       | 2024-01-12    | stream        |
| 2       | 2024-02-20    | stream        |
| 2       | 2024-02-25    | like          |
| 3       | 2024-02-01    | stream        |
| 3       | 2024-02-14    | like          |
| 3       | 2024-03-08    | stream        |
| 3       | 2024-04-22    | stream        |
| 3       | 2024-05-11    | search        |
| 4       | 2024-03-03    | stream        |
| 4       | 2024-03-19    | like          |

---

## Expected Output

**Cohort Retention Matrix (percentages)**

| cohort_month | cohort_size | month_0 | month_1 | month_2 | month_3 | month_4 |
|--------------|-------------|---------|---------|---------|---------|---------|
| 2024-01      | 2           | 100.00  | 100.00  | 50.00   | 0.00    | 50.00   |
| 2024-02      | 1           | 100.00  | 100.00  | 100.00  | 100.00  | —       |
| 2024-03      | 1           | 100.00  | 0.00    | 0.00    | —       | —       |

> **Note:** User 1 and User 2 both first appeared in Jan-2024 (cohort_size = 2). User 3's first activity is Feb-2024, User 4's is Mar-2024. "—" means the period has not elapsed yet relative to available data.

---

## Brute Force Solution

```sql
-- Step 1: Find each user's cohort (first activity month)
-- Step 2: For each user, find all distinct active months
-- Step 3: Cross-join cohorts with a sequence of month offsets
-- Step 4: Left-join actual activity and compute retention

WITH user_cohort AS (
    -- Step 1: Determine the signup cohort for each user
    SELECT
        user_id,
        DATE_TRUNC('month', MIN(activity_date)) AS cohort_month
    FROM user_activity
    GROUP BY user_id
),

user_active_months AS (
    -- Step 2: Get distinct active months per user
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('month', activity_date) AS active_month
    FROM user_activity
),

month_offsets AS (
    -- Step 3: Generate a series of month offsets (0 through 4)
    SELECT 0 AS month_offset
    UNION ALL SELECT 1
    UNION ALL SELECT 2
    UNION ALL SELECT 3
    UNION ALL SELECT 4
),

cohort_grid AS (
    -- Step 4: Cross-join each user's cohort with every offset
    SELECT
        uc.user_id,
        uc.cohort_month,
        mo.month_offset,
        uc.cohort_month + INTERVAL '1' MONTH * mo.month_offset AS target_month
    FROM user_cohort uc
    CROSS JOIN month_offsets mo
),

retention_flags AS (
    -- Step 5: Flag whether each user was active in that target month
    SELECT
        cg.user_id,
        cg.cohort_month,
        cg.month_offset,
        CASE WHEN uam.active_month IS NOT NULL THEN 1 ELSE 0 END AS was_active
    FROM cohort_grid cg
    LEFT JOIN user_active_months uam
        ON  cg.user_id     = uam.user_id
        AND cg.target_month = uam.active_month
)

-- Step 6: Aggregate into the retention matrix
SELECT
    rf.cohort_month,
    COUNT(DISTINCT rf.user_id)                                          AS cohort_size,
    ROUND(100.0 * SUM(CASE WHEN month_offset = 0 THEN was_active END)
        / COUNT(DISTINCT rf.user_id), 2)                                AS month_0,
    ROUND(100.0 * SUM(CASE WHEN month_offset = 1 THEN was_active END)
        / COUNT(DISTINCT rf.user_id), 2)                                AS month_1,
    ROUND(100.0 * SUM(CASE WHEN month_offset = 2 THEN was_active END)
        / COUNT(DISTINCT rf.user_id), 2)                                AS month_2,
    ROUND(100.0 * SUM(CASE WHEN month_offset = 3 THEN was_active END)
        / COUNT(DISTINCT rf.user_id), 2)                                AS month_3,
    ROUND(100.0 * SUM(CASE WHEN month_offset = 4 THEN was_active END)
        / COUNT(DISTINCT rf.user_id), 2)                                AS month_4
FROM retention_flags rf
GROUP BY rf.cohort_month
ORDER BY rf.cohort_month;
```

### Explanation

1. **user_cohort** — Finds the earliest activity month per user, defining their cohort.
2. **user_active_months** — Deduplicates activity to one row per user per month.
3. **month_offsets** — A static list of how many months after signup we want to measure (0–4).
4. **cohort_grid** — Cross-joins users with offsets to build every (user, target_month) pair we need to check.
5. **retention_flags** — Left-joins actual activity onto the grid; a match means the user was retained that month.
6. **Final SELECT** — Pivots the flags into a single row per cohort with retention percentages.

**Drawback:** The number of retention columns is hard-coded. If the data spans 24 months you must add 24 CASE expressions. The CROSS JOIN can also be expensive when there are millions of users.

---

## Optimal Solution

```sql
WITH user_cohort AS (
    SELECT
        user_id,
        DATE_TRUNC('month', MIN(activity_date)) AS cohort_month
    FROM user_activity
    GROUP BY user_id
),

activity_with_cohort AS (
    SELECT
        uc.user_id,
        uc.cohort_month,
        DATE_TRUNC('month', ua.activity_date)                          AS active_month,
        -- Compute the month offset directly from dates
        (EXTRACT(YEAR  FROM DATE_TRUNC('month', ua.activity_date)) -
         EXTRACT(YEAR  FROM uc.cohort_month)) * 12
      + (EXTRACT(MONTH FROM DATE_TRUNC('month', ua.activity_date)) -
         EXTRACT(MONTH FROM uc.cohort_month))                          AS month_offset
    FROM user_activity ua
    JOIN user_cohort uc ON ua.user_id = uc.user_id
),

cohort_sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM user_cohort
    GROUP BY cohort_month
),

retention_counts AS (
    SELECT
        cohort_month,
        month_offset,
        COUNT(DISTINCT user_id) AS retained_users
    FROM activity_with_cohort
    GROUP BY cohort_month, month_offset
)

SELECT
    cs.cohort_month,
    cs.cohort_size,
    rc.month_offset,
    rc.retained_users,
    ROUND(100.0 * rc.retained_users / cs.cohort_size, 2) AS retention_pct
FROM retention_counts rc
JOIN cohort_sizes cs ON rc.cohort_month = cs.cohort_month
ORDER BY cs.cohort_month, rc.month_offset;
```

### Why This Is Better

| Aspect | Brute Force | Optimal |
|--------|------------|---------|
| **Column count** | Hard-coded per offset — brittle and doesn't scale | Dynamic rows — works for any horizon |
| **Join pattern** | CROSS JOIN (users × offsets) explodes row count | Inner JOIN only on actual activity — processes only real data |
| **Scalability** | O(users × offsets) intermediate rows | O(activity rows) — proportional to actual data |
| **Readability** | Wide pivot with repeated CASE expressions | Tidy long-format output, easy to pivot in BI tools |

The optimal solution computes `month_offset` arithmetically from the dates, avoiding both the static offset list and the cross join. The output is in **long format** (one row per cohort × offset), which is the standard input for BI tools like Looker, Tableau, or Metabase. Pivoting to a wide matrix is best done at the presentation layer.

---

## Interviewer Follow-Up Questions

1. **"How would you handle users who churn and then reactivate?"**
   The current query naturally handles reactivation — if a user is inactive in Month 3 but returns in Month 5, month_offset = 5 will show them as retained. To distinguish *continuously retained* from *reactivated*, you would add a flag by checking whether the user was active in *all* prior months using a running count comparison.

2. **"Can you produce a weekly retention matrix instead of monthly?"**
   Replace `DATE_TRUNC('month', ...)` with `DATE_TRUNC('week', ...)` and compute `month_offset` as `(active_week - cohort_week) / 7` using date subtraction. The structure stays identical; only the truncation granularity changes.

3. **"How would you optimize this for a table with billions of rows?"**
   - Pre-aggregate the activity table into a `user_day` or `user_month` summary table.
   - Partition the activity table by `activity_date` and prune scans to the cohort window.
   - Use approximate distinct counts (`APPROX_COUNT_DISTINCT`) for dashboards where exact precision is not critical.

---

## Key Takeaways

- **Cohort analysis** always starts by identifying the cohort key — typically the user's first event month (`MIN(activity_date)`).
- **DATE_TRUNC** is the workhorse function for grouping timestamps into calendar buckets (day, week, month, quarter).
- **Avoid hard-coded pivots in SQL** when the number of columns is data-driven; prefer long-format output and let the BI layer pivot.
- **Month offset arithmetic** (`year_diff * 12 + month_diff`) eliminates the need for a cross-joined sequence table.
- **Retention matrices** are a foundation pattern that extends to revenue retention (dollar-weighted), feature adoption funnels, and subscription churn analysis.
- **Always clarify the retention definition**: "returned at least once" (cumulative) vs. "returned in that exact period" (period-specific) — most interviewers expect period-specific.
