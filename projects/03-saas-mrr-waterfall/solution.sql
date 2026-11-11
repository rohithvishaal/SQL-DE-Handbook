-- ============================================================
-- Project 3: SaaS MRR Waterfall — Reference Solution
-- ============================================================
-- Computes a month-over-month MRR waterfall from billing_events.
-- Categories: New, Expansion, Contraction, Churn, Reactivation
-- Validates: Beginning + New + Expansion - Contraction - Churn
--            + Reactivation = Ending MRR
-- ============================================================
-- Dialect: ANSI SQL (uses standard window functions and CTEs)
-- ============================================================


-- ============================================================
-- STEP 1: Generate a month spine
-- ============================================================
-- We need one row per month covering the full data range.
-- This ensures months with no activity still appear.
-- ============================================================
WITH RECURSIVE month_spine AS (
    -- Anchor: first month in the data
    SELECT DATE '2024-01-01' AS month_start
    UNION ALL
    -- Recurse: add one month at a time
    SELECT CAST(month_start + INTERVAL '1' MONTH AS DATE)
    FROM   month_spine
    WHERE  month_start < DATE '2024-08-01'
),

-- ============================================================
-- STEP 2: Determine each customer's MRR at the END of every
--         month they were (or became) active.
-- ============================================================
-- Strategy: for each month, find the LAST billing event for
-- each customer in or before that month. The new_mrr of that
-- event is their MRR at month-end.
--
-- We also track whether the customer had ANY event before the
-- current month (to distinguish "new this month" from existing).
-- ============================================================

-- 2a. Tag each event with the month it falls into
events_with_month AS (
    SELECT
        event_id,
        customer_id,
        event_type,
        old_mrr,
        new_mrr,
        event_date,
        -- Truncate event_date to the first of its month
        DATE(
            CAST(EXTRACT(YEAR FROM event_date) AS VARCHAR) || '-' ||
            LPAD(CAST(EXTRACT(MONTH FROM event_date) AS VARCHAR), 2, '0') || '-01'
        ) AS event_month
    FROM billing_events
),

-- 2b. For each customer × month, get the net MRR at month-end
--     by taking the last event's new_mrr within or before that month.
--     Also capture first-ever event month to identify "new" customers.
customer_first_month AS (
    SELECT
        customer_id,
        MIN(event_month) AS first_event_month
    FROM events_with_month
    GROUP BY customer_id
),

-- 2c. Build a cross-join of customers × months, then attach MRR
customer_months AS (
    SELECT DISTINCT customer_id
    FROM billing_events
),

customer_month_grid AS (
    SELECT
        cm.customer_id,
        ms.month_start
    FROM customer_months cm
    CROSS JOIN month_spine ms
),

-- 2d. For each customer+month, find the latest event at or before month-end.
--     The new_mrr of that event is the customer's MRR for that month.
latest_event_per_month AS (
    SELECT
        g.customer_id,
        g.month_start,
        e.new_mrr,
        e.event_type,
        e.event_date,
        ROW_NUMBER() OVER (
            PARTITION BY g.customer_id, g.month_start
            ORDER BY e.event_date DESC, e.event_id DESC
        ) AS rn
    FROM customer_month_grid g
    JOIN billing_events e
        ON  e.customer_id = g.customer_id
        AND e.event_date <= g.month_start + INTERVAL '1' MONTH - INTERVAL '1' DAY
            -- event is at or before the last day of the month
),

-- 2e. Keep only the latest event → gives us month-end MRR per customer
customer_mrr_monthly AS (
    SELECT
        customer_id,
        month_start,
        -- If the latest event is a cancellation, MRR = 0
        CASE
            WHEN event_type = 'cancellation' THEN 0.00
            ELSE new_mrr
        END AS mrr
    FROM latest_event_per_month
    WHERE rn = 1
),

-- ============================================================
-- STEP 3: Compute month-over-month MRR deltas per customer
-- ============================================================
-- Compare each customer's MRR this month vs. previous month.
-- A NULL previous-month means the customer didn't exist yet.
-- ============================================================
mrr_with_previous AS (
    SELECT
        cmm.customer_id,
        cmm.month_start,
        cmm.mrr                                                   AS current_mrr,
        LAG(cmm.mrr) OVER (
            PARTITION BY cmm.customer_id
            ORDER BY cmm.month_start
        )                                                          AS previous_mrr,
        cfm.first_event_month
    FROM customer_mrr_monthly cmm
    JOIN customer_first_month cfm
        ON cfm.customer_id = cmm.customer_id
),

-- ============================================================
-- STEP 4: Classify each customer-month into MRR movement type
-- ============================================================
-- Decision tree:
--   previous_mrr IS NULL or month < first_event → skip (pre-existence)
--   first_event_month = current month & prev NULL → New
--   prev = 0 & current > 0 → Reactivation
--   prev IS NULL & current > 0 & first_event_month = month → New
--   prev > 0 & current = 0 → Churn
--   current > prev (both > 0) → Expansion
--   current < prev (both > 0) → Contraction
--   current = prev → no movement
-- ============================================================
mrr_movements AS (
    SELECT
        customer_id,
        month_start,
        current_mrr,
        COALESCE(previous_mrr, 0)                                  AS previous_mrr,
        first_event_month,
        CASE
            -- Brand-new customer: first month they appear & had no prior MRR
            WHEN first_event_month = month_start
                 AND (previous_mrr IS NULL OR previous_mrr = 0)
                 AND current_mrr > 0
                THEN 'new'

            -- Reactivation: was at 0 last month, now > 0, but NOT first month
            WHEN COALESCE(previous_mrr, 0) = 0
                 AND current_mrr > 0
                 AND first_event_month < month_start
                THEN 'reactivation'

            -- Churn: had MRR last month, now at 0
            WHEN previous_mrr > 0 AND current_mrr = 0
                THEN 'churn'

            -- Expansion: MRR increased (both months > 0)
            WHEN previous_mrr > 0 AND current_mrr > previous_mrr
                THEN 'expansion'

            -- Contraction: MRR decreased but not to 0
            WHEN previous_mrr > 0 AND current_mrr < previous_mrr AND current_mrr > 0
                THEN 'contraction'

            -- No change
            ELSE 'no_change'
        END AS movement_type,

        -- Delta calculation
        CASE
            WHEN first_event_month = month_start
                 AND (previous_mrr IS NULL OR previous_mrr = 0)
                 AND current_mrr > 0
                THEN current_mrr                                   -- New: full amount

            WHEN COALESCE(previous_mrr, 0) = 0
                 AND current_mrr > 0
                 AND first_event_month < month_start
                THEN current_mrr                                   -- Reactivation: full amount

            WHEN previous_mrr > 0 AND current_mrr = 0
                THEN previous_mrr                                  -- Churn: full lost amount

            WHEN previous_mrr > 0 AND current_mrr > previous_mrr
                THEN current_mrr - previous_mrr                    -- Expansion: delta

            WHEN previous_mrr > 0 AND current_mrr < previous_mrr AND current_mrr > 0
                THEN previous_mrr - current_mrr                    -- Contraction: delta (positive)

            ELSE 0
        END AS mrr_delta

    FROM mrr_with_previous
    -- Only consider months from the customer's first event onward
    WHERE month_start >= first_event_month
),

-- ============================================================
-- STEP 5: Aggregate into the MRR Waterfall
-- ============================================================
-- Sum deltas by month and movement type to build the waterfall.
-- ============================================================
waterfall_components AS (
    SELECT
        month_start,
        SUM(CASE WHEN movement_type = 'new'          THEN mrr_delta ELSE 0 END) AS new_mrr,
        SUM(CASE WHEN movement_type = 'expansion'    THEN mrr_delta ELSE 0 END) AS expansion_mrr,
        SUM(CASE WHEN movement_type = 'contraction'  THEN mrr_delta ELSE 0 END) AS contraction_mrr,
        SUM(CASE WHEN movement_type = 'churn'        THEN mrr_delta ELSE 0 END) AS churn_mrr,
        SUM(CASE WHEN movement_type = 'reactivation' THEN mrr_delta ELSE 0 END) AS reactivation_mrr
    FROM mrr_movements
    GROUP BY month_start
),

-- ============================================================
-- STEP 6: Compute Beginning & Ending MRR per month
-- ============================================================
-- Beginning MRR = sum of all active customers' MRR from prior month
-- Ending MRR   = sum of all active customers' MRR this month
-- ============================================================
monthly_totals AS (
    SELECT
        month_start,
        SUM(mrr) AS ending_mrr
    FROM customer_mrr_monthly
    GROUP BY month_start
),

waterfall AS (
    SELECT
        wc.month_start,
        -- Beginning MRR = previous month's ending MRR (0 for first month)
        COALESCE(LAG(mt.ending_mrr) OVER (ORDER BY wc.month_start), 0) AS beginning_mrr,
        wc.new_mrr,
        wc.expansion_mrr,
        wc.contraction_mrr,
        wc.churn_mrr,
        wc.reactivation_mrr,
        mt.ending_mrr,
        -- Net new MRR = all positive movements minus negative ones
        (wc.new_mrr + wc.expansion_mrr + wc.reactivation_mrr
         - wc.contraction_mrr - wc.churn_mrr)                        AS net_new_mrr
    FROM waterfall_components wc
    JOIN monthly_totals mt ON mt.month_start = wc.month_start
)

-- ============================================================
-- FINAL OUTPUT: MRR Waterfall with Reconciliation Check
-- ============================================================
SELECT
    month_start,
    beginning_mrr,
    new_mrr,
    expansion_mrr,
    contraction_mrr,
    churn_mrr,
    reactivation_mrr,
    net_new_mrr,
    ending_mrr,
    -- Reconciliation: this should always equal ending_mrr
    (beginning_mrr + new_mrr + expansion_mrr
     - contraction_mrr - churn_mrr + reactivation_mrr)               AS calculated_ending_mrr,
    -- Balance check flag
    CASE
        WHEN ending_mrr = (beginning_mrr + new_mrr + expansion_mrr
                           - contraction_mrr - churn_mrr + reactivation_mrr)
            THEN 'BALANCED'
        ELSE 'MISMATCH'
    END                                                               AS reconciliation_status
FROM waterfall
ORDER BY month_start;


-- ============================================================
-- BONUS QUERY A: Customer-Level Movement Detail
-- ============================================================
-- Shows every customer's MRR movement per month for drill-down.
-- Useful for debugging and auditing the waterfall.
-- ============================================================
/*
SELECT
    month_start,
    customer_id,
    previous_mrr,
    current_mrr,
    movement_type,
    mrr_delta
FROM mrr_movements
WHERE movement_type <> 'no_change'
ORDER BY month_start, customer_id;
*/


-- ============================================================
-- BONUS QUERY B: SaaS Quick Ratio
-- ============================================================
-- Quick Ratio = (New + Expansion + Reactivation) / (Contraction + Churn)
-- A ratio > 4 is considered excellent.
-- ============================================================
/*
SELECT
    month_start,
    new_mrr + expansion_mrr + reactivation_mrr                       AS growth_mrr,
    contraction_mrr + churn_mrr                                      AS lost_mrr,
    CASE
        WHEN (contraction_mrr + churn_mrr) = 0 THEN NULL             -- avoid division by zero
        ELSE ROUND(
            (new_mrr + expansion_mrr + reactivation_mrr) * 1.0
            / (contraction_mrr + churn_mrr),
            2
        )
    END                                                              AS quick_ratio
FROM waterfall
ORDER BY month_start;
*/


-- ============================================================
-- BONUS QUERY C: Net Revenue Retention (NRR) %
-- ============================================================
-- NRR = (Beginning MRR + Expansion - Contraction - Churn) / Beginning MRR
-- An NRR > 100% means existing customers are growing faster than churning.
-- ============================================================
/*
SELECT
    month_start,
    beginning_mrr,
    CASE
        WHEN beginning_mrr = 0 THEN NULL
        ELSE ROUND(
            (beginning_mrr + expansion_mrr - contraction_mrr - churn_mrr)
            * 100.0 / beginning_mrr,
            1
        )
    END                                                              AS nrr_pct
FROM waterfall
ORDER BY month_start;
*/
