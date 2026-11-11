-- ============================================================================
-- Project 1: Clickstream Sessionization & Multi-Touch Attribution
-- Reference Solution (Dialect-Agnostic ANSI SQL with Dialect Notes)
-- ============================================================================
--
-- Pipeline Architecture:
--   Step 0 (Pattern): Semi-Structured JSON Ingestion & Normalization (reference)
--   Step 1: 30-Minute Idle-Timeout Session Reconstruction (LAG + Cumulative SUM)
--   Step 2: Session-Level Metrics & Funnel Aggregation
--   Step 3: Conversion Path Construction (Lookback Window per Purchase)
--   Step 4: Multi-Touch Attribution (First-Touch, Last-Touch, Linear)
--   Step 5: Executive Channel Performance Report & Reconciliation Check
--
-- Dialect Notes:
--   - Interval arithmetic uses ANSI SQL `INTERVAL '30' MINUTE`.
--     * BigQuery:   TIMESTAMP_DIFF(event_timestamp, prev_event_timestamp, MINUTE) > 30
--     * Snowflake:  DATEDIFF('minute', prev_event_timestamp, event_timestamp) > 30
--     * Spark/DBX:  (unix_timestamp(event_timestamp) - unix_timestamp(prev_event_timestamp)) > 1800
--   - Duration calculation uses `EXTRACT(EPOCH FROM ...)` (PostgreSQL / DuckDB / Trino).
--     * Snowflake:  DATEDIFF('second', session_start, session_end)
--     * BigQuery:   TIMESTAMP_DIFF(session_end, session_start, SECOND)
-- ============================================================================


-- ============================================================================
-- STEP 0 (Reference Pattern): Raw JSON Click Ingestion & Normalization
-- ============================================================================
-- In production, raw clickstream events often land in a staging table as JSON
-- strings or VARIANT/JSONB columns (e.g., `raw_event_json`). Before running
-- sessionization, an ingestion CTE or dbt staging model parses and casts
-- those semi-structured fields into the typed `raw_clicks` schema:
--
--   SELECT
--       JSON_VALUE(payload, '$.event_id')                       AS event_id,
--       JSON_VALUE(payload, '$.user_id')                        AS user_id,
--       CAST(JSON_VALUE(payload, '$.event_ts') AS TIMESTAMP)    AS event_timestamp,
--       LOWER(JSON_VALUE(payload, '$.event_type'))              AS event_type,
--       JSON_VALUE(payload, '$.page.url')                       AS page_url,
--       JSON_VALUE(payload, '$.page.referrer')                  AS referrer_url,
--       LOWER(JSON_VALUE(payload, '$.utm.source'))              AS utm_source,
--       LOWER(JSON_VALUE(payload, '$.utm.medium'))              AS utm_medium,
--       JSON_VALUE(payload, '$.utm.campaign')                   AS utm_campaign,
--       LOWER(JSON_VALUE(payload, '$.device.type'))             AS device_type,
--       UPPER(JSON_VALUE(payload, '$.geo.country'))             AS country_code
--   FROM raw_clickstream_landing;
--
-- Our `raw_clicks` table represents this normalized, typed staging layer.
-- ============================================================================


-- ============================================================================
-- QUERY 1: Reconstruct User Sessions & Compute Session-Level Metrics
-- ============================================================================
-- Purpose:
--   Assigns a deterministic `session_id` to every event in `raw_clicks` using
--   a 30-minute inactivity threshold, then aggregates page views, duration,
--   funnel actions, bounce status, and attributed order revenue per session.
-- ============================================================================

WITH event_with_lag AS (
    -- 1A. Fetch the timestamp of the user's immediately preceding event.
    --     Including `event_id` in ORDER BY guarantees deterministic ordering
    --     if two events for the same user share an identical timestamp.
    SELECT
        rc.event_id,
        rc.user_id,
        rc.event_timestamp,
        rc.event_type,
        rc.page_url,
        rc.referrer_url,
        rc.utm_source,
        rc.utm_medium,
        rc.utm_campaign,
        rc.device_type,
        rc.country_code,
        LAG(rc.event_timestamp) OVER (
            PARTITION BY rc.user_id
            ORDER BY rc.event_timestamp ASC, rc.event_id ASC
        ) AS prev_event_timestamp
    FROM raw_clicks rc
),

session_boundaries AS (
    -- 1B. Flag session boundaries whenever:
    --     (a) It is the user's very first recorded event (prev_event_timestamp IS NULL), OR
    --     (b) More than 30 minutes have elapsed since their previous event.
    SELECT
        ewl.*,
        CASE
            WHEN ewl.prev_event_timestamp IS NULL
              OR ewl.event_timestamp > ewl.prev_event_timestamp + INTERVAL '30' MINUTE
            THEN 1
            ELSE 0
        END AS is_new_session
    FROM event_with_lag ewl
),

sessionized_events AS (
    -- 1C. Running sum of boundary flags creates a monotonically increasing
    --     session counter per user (`user_session_num`).
    --     IMPORTANT: Explicit `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`
    --     prevents RANGE-frame collisions when timestamps are equal.
    SELECT
        sb.*,
        SUM(sb.is_new_session) OVER (
            PARTITION BY sb.user_id
            ORDER BY sb.event_timestamp ASC, sb.event_id ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS user_session_num,
        sb.user_id || '-S' || CAST(
            SUM(sb.is_new_session) OVER (
                PARTITION BY sb.user_id
                ORDER BY sb.event_timestamp ASC, sb.event_id ASC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS VARCHAR(10)
        ) AS session_id
    FROM session_boundaries sb
),

session_events_ranked AS (
    -- 1D. Compute per-session ascending and descending event sequence numbers.
    --     Kept in a separate CTE because ANSI SQL engines disallow nesting a
    --     window function (`SUM`) inside another window function's PARTITION BY.
    SELECT
        se.event_id,
        se.user_id,
        se.session_id,
        se.user_session_num,
        se.event_timestamp,
        se.event_type,
        se.page_url,
        se.utm_source,
        se.utm_medium,
        se.utm_campaign,
        se.device_type,
        se.country_code,
        ROW_NUMBER() OVER (
            PARTITION BY se.session_id
            ORDER BY se.event_timestamp ASC, se.event_id ASC
        ) AS seq_asc,
        ROW_NUMBER() OVER (
            PARTITION BY se.session_id
            ORDER BY se.event_timestamp DESC, se.event_id DESC
        ) AS seq_desc
    FROM sessionized_events se
),

session_channels AS (
    -- 1E. Determine each session's landing marketing channel from the earliest
    --     event in the session (fallback: 'Direct').
    SELECT
        ser.session_id,
        COALESCE(mc.channel_name, 'Direct') AS entry_channel,
        COALESCE(mc.channel_group, 'direct') AS entry_channel_group
    FROM session_events_ranked ser
    LEFT JOIN marketing_channels mc
        ON ser.utm_source = mc.utm_source
       AND ser.utm_medium = mc.utm_medium
    WHERE ser.seq_asc = 1
),

session_metrics AS (
    -- 1F. Aggregate session KPIs: timestamps, duration, page views, funnel flags,
    --     entry/exit pages, and bounce indicator.
    SELECT
        ser.session_id,
        ser.user_id,
        ser.user_session_num,
        sc.entry_channel,
        sc.entry_channel_group,
        MIN(ser.device_type)                                        AS device_type,
        MIN(ser.country_code)                                       AS country_code,
        MIN(ser.event_timestamp)                                    AS session_start,
        MAX(ser.event_timestamp)                                    AS session_end,
        ROUND(
            EXTRACT(EPOCH FROM (MAX(ser.event_timestamp) - MIN(ser.event_timestamp))) / 60.0,
            2
        )                                                           AS duration_minutes,
        COUNT(*)                                                    AS total_events,
        COUNT(DISTINCT pv.page_view_id)                             AS page_view_count,
        COALESCE(SUM(pv.time_on_page_s), 0)                         AS total_engaged_seconds,
        MAX(CASE WHEN ser.seq_asc = 1 THEN ser.page_url END)        AS entry_page,
        MAX(CASE WHEN ser.seq_desc = 1 THEN ser.page_url END)       AS exit_page,
        SUM(CASE WHEN ser.event_type = 'add_to_cart' THEN 1 ELSE 0 END) AS add_to_cart_events,
        MAX(CASE WHEN ser.event_type = 'purchase' THEN 1 ELSE 0 END)    AS is_converted_session,
        -- A bounce is a session with only 1 event and at most 1 page view
        CASE
            WHEN COUNT(*) = 1 AND COUNT(DISTINCT pv.page_view_id) <= 1 THEN 1
            ELSE 0
        END                                                         AS is_bounce
    FROM session_events_ranked ser
    LEFT JOIN page_views pv
        ON ser.event_id = pv.event_id
    LEFT JOIN session_channels sc
        ON ser.session_id = sc.session_id
    GROUP BY
        ser.session_id,
        ser.user_id,
        ser.user_session_num,
        sc.entry_channel,
        sc.entry_channel_group
)

SELECT
    sm.session_id,
    sm.user_id,
    sm.entry_channel,
    sm.device_type,
    sm.session_start,
    sm.session_end,
    sm.duration_minutes,
    sm.total_events,
    sm.page_view_count,
    sm.entry_page,
    sm.exit_page,
    sm.add_to_cart_events,
    sm.is_bounce,
    sm.is_converted_session,
    COALESCE(SUM(p.revenue), 0.00) AS session_revenue
FROM session_metrics sm
LEFT JOIN purchases p
    ON sm.user_id = p.user_id
   AND p.purchase_timestamp >= sm.session_start
   AND p.purchase_timestamp <= sm.session_end
GROUP BY
    sm.session_id,
    sm.user_id,
    sm.entry_channel,
    sm.device_type,
    sm.session_start,
    sm.session_end,
    sm.duration_minutes,
    sm.total_events,
    sm.page_view_count,
    sm.entry_page,
    sm.exit_page,
    sm.add_to_cart_events,
    sm.is_bounce,
    sm.is_converted_session
ORDER BY sm.user_id, sm.session_start;


-- ============================================================================
-- QUERY 2: Multi-Touch Attribution & Channel Performance Summary Report
-- ============================================================================
-- Purpose:
--   For each purchase, reconstructs the user's ordered marketing touchpoint
--   path within a 30-day lookback window (bounded by the user's previous
--   purchase so prior conversions' touches are not double-counted), and
--   attributes order revenue using:
--     1. First-Touch Attribution (100% to earliest touchpoint in path)
--     2. Last-Touch Attribution  (100% to latest touchpoint before purchase)
--     3. Linear Attribution      (equal split across distinct channels touched)
-- ============================================================================

WITH purchase_windows AS (
    -- 2A. Define each order's conversion lookback window:
    --     Starts immediately after the user's previous purchase (or 30 days prior,
    --     whichever is later) and ends at the current purchase_timestamp.
    SELECT
        p.order_id,
        p.user_id,
        p.purchase_timestamp,
        p.revenue,
        LAG(p.purchase_timestamp) OVER (
            PARTITION BY p.user_id
            ORDER BY p.purchase_timestamp ASC, p.order_id ASC
        ) AS prev_purchase_timestamp
    FROM purchases p
),

user_touchpoints AS (
    -- 2B. Extract every click event carrying marketing channel metadata and map
    --     raw UTM pairs to canonical channel names via `marketing_channels`.
    SELECT
        rc.event_id,
        rc.user_id,
        rc.event_timestamp,
        COALESCE(mc.channel_id, 9)               AS channel_id,
        COALESCE(mc.channel_name, 'Direct')      AS channel_name,
        COALESCE(mc.channel_group, 'direct')     AS channel_group
    FROM raw_clicks rc
    LEFT JOIN marketing_channels mc
        ON rc.utm_source = mc.utm_source
       AND rc.utm_medium = mc.utm_medium
    WHERE rc.utm_source IS NOT NULL
),

conversion_path_touches AS (
    -- 2C. Match each order to all marketing touchpoints inside its attribution
    --     window, and rank them chronologically from first touch to last touch.
    SELECT
        pw.order_id,
        pw.user_id,
        pw.purchase_timestamp,
        pw.revenue,
        ut.event_id,
        ut.event_timestamp,
        ut.channel_id,
        ut.channel_name,
        ut.channel_group,
        ROW_NUMBER() OVER (
            PARTITION BY pw.order_id
            ORDER BY ut.event_timestamp ASC, ut.event_id ASC
        ) AS touch_order_asc,
        ROW_NUMBER() OVER (
            PARTITION BY pw.order_id
            ORDER BY ut.event_timestamp DESC, ut.event_id DESC
        ) AS touch_order_desc
    FROM purchase_windows pw
    INNER JOIN user_touchpoints ut
        ON pw.user_id = ut.user_id
       AND ut.event_timestamp <= pw.purchase_timestamp
       AND ut.event_timestamp >= pw.purchase_timestamp - INTERVAL '30' DAY
       AND (
           pw.prev_purchase_timestamp IS NULL
           OR ut.event_timestamp > pw.prev_purchase_timestamp
       )
),

distinct_order_channels AS (
    -- 2D. Collapse multiple touches from the same channel within one conversion
    --     window so Linear Attribution splits credit evenly across *distinct*
    --     channels in the path, while tracking whether each channel held the
    --     first touch or last touch position.
    SELECT
        cpt.order_id,
        cpt.user_id,
        cpt.revenue,
        cpt.channel_id,
        cpt.channel_name,
        cpt.channel_group,
        MIN(cpt.touch_order_asc)                        AS earliest_touch_pos,
        MIN(cpt.touch_order_desc)                       AS latest_touch_pos,
        COUNT(*)                                        AS channel_touch_count,
        COUNT(*) OVER (PARTITION BY cpt.order_id)       AS distinct_channels_in_path
    FROM conversion_path_touches cpt
    GROUP BY
        cpt.order_id,
        cpt.user_id,
        cpt.revenue,
        cpt.channel_id,
        cpt.channel_name,
        cpt.channel_group
),

attributed_order_channels AS (
    -- 2E. Compute First-Touch, Last-Touch, and Linear attributed revenue per
    --     (order_id, channel_name) pair using high-precision DECIMAL(12,4)
    --     to avoid intermediate rounding drift.
    SELECT
        doc.order_id,
        doc.user_id,
        doc.revenue                                     AS total_order_revenue,
        doc.channel_id,
        doc.channel_name,
        doc.channel_group,
        doc.distinct_channels_in_path,
        CASE
            WHEN doc.earliest_touch_pos = 1 THEN CAST(doc.revenue AS DECIMAL(12, 4))
            ELSE 0.0000
        END                                             AS first_touch_revenue,
        CASE
            WHEN doc.latest_touch_pos = 1 THEN CAST(doc.revenue AS DECIMAL(12, 4))
            ELSE 0.0000
        END                                             AS last_touch_revenue,
        CAST(doc.revenue AS DECIMAL(12, 4))
            / doc.distinct_channels_in_path             AS linear_revenue
    FROM distinct_order_channels doc
)

-- 2F. Order-level attribution breakdown (auditable per order & channel)
SELECT
    aoc.order_id,
    aoc.user_id,
    aoc.channel_name,
    aoc.distinct_channels_in_path,
    aoc.total_order_revenue,
    ROUND(aoc.first_touch_revenue, 2) AS first_touch_revenue,
    ROUND(aoc.last_touch_revenue, 2)  AS last_touch_revenue,
    ROUND(aoc.linear_revenue, 2)      AS linear_revenue
FROM attributed_order_channels aoc
ORDER BY aoc.order_id, aoc.channel_name;


-- ============================================================================
-- QUERY 3: Executive Channel Performance Summary (Sessions + Attribution)
-- ============================================================================
-- Purpose:
--   Combines session-level engagement metrics (sessions, bounce rate, session
--   conversion rate) with First-Touch, Last-Touch, and Linear attributed
--   revenue for every marketing channel in `marketing_channels`.
-- ============================================================================

WITH event_with_lag AS (
    SELECT
        rc.event_id,
        rc.user_id,
        rc.event_timestamp,
        rc.event_type,
        rc.utm_source,
        rc.utm_medium,
        LAG(rc.event_timestamp) OVER (
            PARTITION BY rc.user_id
            ORDER BY rc.event_timestamp ASC, rc.event_id ASC
        ) AS prev_event_timestamp
    FROM raw_clicks rc
),

session_boundaries AS (
    SELECT
        ewl.*,
        CASE
            WHEN ewl.prev_event_timestamp IS NULL
              OR ewl.event_timestamp > ewl.prev_event_timestamp + INTERVAL '30' MINUTE
            THEN 1
            ELSE 0
        END AS is_new_session
    FROM event_with_lag ewl
),

sessionized AS (
    SELECT
        sb.*,
        sb.user_id || '-S' || CAST(
            SUM(sb.is_new_session) OVER (
                PARTITION BY sb.user_id
                ORDER BY sb.event_timestamp ASC, sb.event_id ASC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS VARCHAR(10)
        ) AS session_id
    FROM session_boundaries sb
),

session_ranked AS (
    SELECT
        s.*,
        ROW_NUMBER() OVER (
            PARTITION BY s.session_id
            ORDER BY s.event_timestamp ASC, s.event_id ASC
        ) AS seq_asc
    FROM sessionized s
),

session_summary AS (
    SELECT
        sr.session_id,
        MAX(CASE WHEN sr.seq_asc = 1 THEN COALESCE(mc.channel_name, 'Direct') END) AS entry_channel,
        MAX(CASE WHEN sr.event_type = 'purchase' THEN 1 ELSE 0 END)                AS is_converted,
        CASE
            WHEN COUNT(*) = 1 AND COUNT(DISTINCT pv.page_view_id) <= 1 THEN 1
            ELSE 0
        END                                                                        AS is_bounce
    FROM session_ranked sr
    LEFT JOIN marketing_channels mc
        ON sr.utm_source = mc.utm_source
       AND sr.utm_medium = mc.utm_medium
       AND sr.seq_asc = 1
    LEFT JOIN page_views pv
        ON sr.event_id = pv.event_id
    GROUP BY sr.session_id
),

channel_sessions AS (
    SELECT
        ss.entry_channel                                    AS channel_name,
        COUNT(*)                                            AS total_sessions,
        SUM(ss.is_bounce)                                   AS bounced_sessions,
        SUM(ss.is_converted)                                AS converted_sessions
    FROM session_summary ss
    GROUP BY ss.entry_channel
),

purchase_windows AS (
    SELECT
        p.order_id,
        p.user_id,
        p.purchase_timestamp,
        p.revenue,
        LAG(p.purchase_timestamp) OVER (
            PARTITION BY p.user_id
            ORDER BY p.purchase_timestamp ASC, p.order_id ASC
        ) AS prev_purchase_timestamp
    FROM purchases p
),

conversion_path_touches AS (
    SELECT
        pw.order_id,
        pw.revenue,
        COALESCE(mc.channel_name, 'Direct') AS channel_name,
        ROW_NUMBER() OVER (
            PARTITION BY pw.order_id
            ORDER BY rc.event_timestamp ASC, rc.event_id ASC
        ) AS touch_order_asc,
        ROW_NUMBER() OVER (
            PARTITION BY pw.order_id
            ORDER BY rc.event_timestamp DESC, rc.event_id DESC
        ) AS touch_order_desc
    FROM purchase_windows pw
    INNER JOIN raw_clicks rc
        ON pw.user_id = rc.user_id
       AND rc.utm_source IS NOT NULL
       AND rc.event_timestamp <= pw.purchase_timestamp
       AND rc.event_timestamp >= pw.purchase_timestamp - INTERVAL '30' DAY
       AND (
           pw.prev_purchase_timestamp IS NULL
           OR rc.event_timestamp > pw.prev_purchase_timestamp
       )
    LEFT JOIN marketing_channels mc
        ON rc.utm_source = mc.utm_source
       AND rc.utm_medium = mc.utm_medium
),

distinct_order_channels AS (
    SELECT
        cpt.order_id,
        cpt.revenue,
        cpt.channel_name,
        MIN(cpt.touch_order_asc)                    AS earliest_touch_pos,
        MIN(cpt.touch_order_desc)                   AS latest_touch_pos,
        COUNT(*) OVER (PARTITION BY cpt.order_id)   AS distinct_channels_in_path
    FROM conversion_path_touches cpt
    GROUP BY
        cpt.order_id,
        cpt.revenue,
        cpt.channel_name
),

channel_attribution AS (
    SELECT
        doc.channel_name,
        COUNT(DISTINCT CASE WHEN doc.earliest_touch_pos = 1 THEN doc.order_id END) AS first_touch_orders,
        COUNT(DISTINCT CASE WHEN doc.latest_touch_pos = 1 THEN doc.order_id END)   AS last_touch_orders,
        COUNT(DISTINCT doc.order_id)                                               AS assisted_or_closed_orders,
        SUM(CASE WHEN doc.earliest_touch_pos = 1 THEN CAST(doc.revenue AS DECIMAL(12, 4)) ELSE 0 END) AS first_touch_rev,
        SUM(CASE WHEN doc.latest_touch_pos = 1 THEN CAST(doc.revenue AS DECIMAL(12, 4)) ELSE 0 END)   AS last_touch_rev,
        SUM(CAST(doc.revenue AS DECIMAL(12, 4)) / doc.distinct_channels_in_path)                      AS linear_rev
    FROM distinct_order_channels doc
    GROUP BY doc.channel_name
)

SELECT
    mc.channel_name,
    mc.channel_group,
    COALESCE(cs.total_sessions, 0)                                                  AS total_sessions,
    COALESCE(cs.bounced_sessions, 0)                                                AS bounced_sessions,
    ROUND(
        100.0 * COALESCE(cs.bounced_sessions, 0) / NULLIF(cs.total_sessions, 0),
        2
    )                                                                               AS bounce_rate_pct,
    COALESCE(cs.converted_sessions, 0)                                              AS converted_sessions,
    ROUND(
        100.0 * COALESCE(cs.converted_sessions, 0) / NULLIF(cs.total_sessions, 0),
        2
    )                                                                               AS session_cvr_pct,
    COALESCE(ca.first_touch_orders, 0)                                              AS first_touch_orders,
    COALESCE(ca.last_touch_orders, 0)                                               AS last_touch_orders,
    COALESCE(ca.assisted_or_closed_orders, 0)                                       AS touched_orders,
    ROUND(COALESCE(ca.first_touch_rev, 0.00), 2)                                    AS first_touch_revenue,
    ROUND(COALESCE(ca.last_touch_rev, 0.00), 2)                                     AS last_touch_revenue,
    ROUND(COALESCE(ca.linear_rev, 0.00), 2)                                         AS linear_revenue
FROM marketing_channels mc
LEFT JOIN channel_sessions cs
    ON mc.channel_name = cs.channel_name
LEFT JOIN channel_attribution ca
    ON mc.channel_name = ca.channel_name
ORDER BY
    linear_revenue DESC,
    total_sessions DESC,
    mc.channel_name ASC;


-- ============================================================================
-- QUERY 4: Attribution Reconciliation Check
-- ============================================================================
-- Purpose:
--   Validates conservation of revenue across all three attribution models:
--   First-Touch Total == Last-Touch Total == Linear Total == Gross Revenue.
--   Any non-zero variance indicates dropped orders or overlapping windows.
-- ============================================================================

WITH purchase_windows AS (
    SELECT
        p.order_id,
        p.user_id,
        p.purchase_timestamp,
        p.revenue,
        LAG(p.purchase_timestamp) OVER (
            PARTITION BY p.user_id
            ORDER BY p.purchase_timestamp ASC, p.order_id ASC
        ) AS prev_purchase_timestamp
    FROM purchases p
),

conversion_path_touches AS (
    SELECT
        pw.order_id,
        pw.revenue,
        COALESCE(mc.channel_name, 'Direct') AS channel_name,
        ROW_NUMBER() OVER (
            PARTITION BY pw.order_id
            ORDER BY rc.event_timestamp ASC, rc.event_id ASC
        ) AS touch_order_asc,
        ROW_NUMBER() OVER (
            PARTITION BY pw.order_id
            ORDER BY rc.event_timestamp DESC, rc.event_id DESC
        ) AS touch_order_desc
    FROM purchase_windows pw
    INNER JOIN raw_clicks rc
        ON pw.user_id = rc.user_id
       AND rc.utm_source IS NOT NULL
       AND rc.event_timestamp <= pw.purchase_timestamp
       AND rc.event_timestamp >= pw.purchase_timestamp - INTERVAL '30' DAY
       AND (
           pw.prev_purchase_timestamp IS NULL
           OR rc.event_timestamp > pw.prev_purchase_timestamp
       )
    LEFT JOIN marketing_channels mc
        ON rc.utm_source = mc.utm_source
       AND rc.utm_medium = mc.utm_medium
),

distinct_order_channels AS (
    SELECT
        cpt.order_id,
        cpt.revenue,
        cpt.channel_name,
        MIN(cpt.touch_order_asc)                    AS earliest_touch_pos,
        MIN(cpt.touch_order_desc)                   AS latest_touch_pos,
        COUNT(*) OVER (PARTITION BY cpt.order_id)   AS distinct_channels_in_path
    FROM conversion_path_touches cpt
    GROUP BY
        cpt.order_id,
        cpt.revenue,
        cpt.channel_name
),

model_totals AS (
    SELECT
        ROUND(SUM(CASE WHEN earliest_touch_pos = 1 THEN CAST(revenue AS DECIMAL(12, 4)) ELSE 0 END), 2) AS total_first_touch,
        ROUND(SUM(CASE WHEN latest_touch_pos = 1 THEN CAST(revenue AS DECIMAL(12, 4)) ELSE 0 END), 2)   AS total_last_touch,
        ROUND(SUM(CAST(revenue AS DECIMAL(12, 4)) / distinct_channels_in_path), 2)                      AS total_linear
    FROM distinct_order_channels
),

gross_revenue AS (
    SELECT ROUND(SUM(revenue), 2) AS total_gross_revenue
    FROM purchases
)

SELECT
    gr.total_gross_revenue,
    mt.total_first_touch,
    mt.total_last_touch,
    mt.total_linear,
    gr.total_gross_revenue - mt.total_first_touch AS first_touch_variance,
    gr.total_gross_revenue - mt.total_last_touch  AS last_touch_variance,
    gr.total_gross_revenue - mt.total_linear      AS linear_variance
FROM gross_revenue gr
CROSS JOIN model_totals mt;
