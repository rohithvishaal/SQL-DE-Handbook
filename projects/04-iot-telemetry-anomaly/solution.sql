-- ============================================================
-- Project 4: IoT Telemetry Anomaly Detection — Reference Solution
-- ============================================================
-- This solution walks through a complete telemetry pipeline:
--   Step 1: Deduplicate raw sensor readings
--   Step 2: Compute multi-scale rolling moving averages
--   Step 3: Calculate Z-scores for anomaly detection
--   Step 4: Classify anomalies by severity using thresholds
--   Step 5: Produce final analysis-ready output
--
-- Dialect: ANSI SQL with window functions
-- ============================================================


-- ============================================================
-- STEP 1: DEDUPLICATE SENSOR READINGS
-- ============================================================
-- Problem: The same reading can arrive multiple times due to
-- network retransmissions (same device_id + measured_at +
-- packet_seq). We also see late arrivals that duplicate an
-- existing reading.
--
-- Strategy: Use ROW_NUMBER() partitioned by the natural key
-- (device_id, measured_at, packet_seq), ordered by ingested_at
-- ASC to keep the EARLIEST arrival. Row number = 1 wins.
-- ============================================================

WITH deduplicated AS (
    SELECT
        reading_id,
        device_id,
        value,
        measured_at,
        ingested_at,
        packet_seq,
        ROW_NUMBER() OVER (
            PARTITION BY device_id, measured_at, packet_seq
            ORDER BY ingested_at ASC, reading_id ASC
        ) AS rn
    FROM sensor_readings
),

-- Keep only the first arrival of each unique reading
clean_readings AS (
    SELECT
        reading_id,
        device_id,
        value,
        measured_at,
        ingested_at,
        packet_seq
    FROM deduplicated
    WHERE rn = 1
),


-- ============================================================
-- STEP 2: COMPUTE MULTI-SCALE ROLLING MOVING AVERAGES
-- ============================================================
-- We compute three moving averages per device, ordered by
-- measurement time:
--   • MA_5:  5-reading window  (short-term smoothing)
--   • MA_15: 15-reading window (medium-term trend)
--   • MA_60: 60-reading window (long-term baseline)
--
-- We also compute the rolling standard deviation over the
-- 15-reading window, which we'll need for Z-score calculation.
--
-- Window spec: ROWS BETWEEN N PRECEDING AND CURRENT ROW
-- ensures we look backward only (causal / non-leaking).
-- ============================================================

moving_averages AS (
    SELECT
        cr.reading_id,
        cr.device_id,
        cr.value,
        cr.measured_at,
        cr.ingested_at,
        cr.packet_seq,

        -- Short-term: 5-reading moving average
        AVG(cr.value) OVER (
            PARTITION BY cr.device_id
            ORDER BY cr.measured_at
            ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
        ) AS ma_5,

        -- Medium-term: 15-reading moving average
        AVG(cr.value) OVER (
            PARTITION BY cr.device_id
            ORDER BY cr.measured_at
            ROWS BETWEEN 14 PRECEDING AND CURRENT ROW
        ) AS ma_15,

        -- Long-term: 60-reading moving average (baseline)
        AVG(cr.value) OVER (
            PARTITION BY cr.device_id
            ORDER BY cr.measured_at
            ROWS BETWEEN 59 PRECEDING AND CURRENT ROW
        ) AS ma_60,

        -- Rolling standard deviation over 15-reading window
        -- Used for Z-score computation in the next step
        STDDEV_POP(cr.value) OVER (
            PARTITION BY cr.device_id
            ORDER BY cr.measured_at
            ROWS BETWEEN 14 PRECEDING AND CURRENT ROW
        ) AS rolling_stddev_15,

        -- Rolling mean over 15-reading window (same as ma_15,
        -- but explicit for clarity in Z-score formula)
        AVG(cr.value) OVER (
            PARTITION BY cr.device_id
            ORDER BY cr.measured_at
            ROWS BETWEEN 14 PRECEDING AND CURRENT ROW
        ) AS rolling_mean_15,

        -- Count of readings in the 15-reading window
        -- (useful to know if we have enough data for reliable stats)
        COUNT(*) OVER (
            PARTITION BY cr.device_id
            ORDER BY cr.measured_at
            ROWS BETWEEN 14 PRECEDING AND CURRENT ROW
        ) AS window_size_15

    FROM clean_readings cr
),


-- ============================================================
-- STEP 3: CALCULATE Z-SCORES FOR ANOMALY DETECTION
-- ============================================================
-- Z-score = (value - rolling_mean) / rolling_stddev
--
-- A Z-score tells us how many standard deviations a reading
-- is from the rolling mean. We use the 15-reading window
-- for stability.
--
-- Guard against division by zero: if stddev = 0 (all values
-- identical in the window), Z-score is 0 (no anomaly).
--
-- We also require a minimum window size of 5 readings before
-- computing meaningful Z-scores (avoids false positives on
-- startup).
-- ============================================================

zscore_calc AS (
    SELECT
        ma.*,

        -- Z-score: how many stddevs away from the rolling mean
        CASE
            WHEN rolling_stddev_15 = 0 THEN 0
            WHEN window_size_15 < 5 THEN 0  -- not enough data yet
            ELSE (value - rolling_mean_15) / rolling_stddev_15
        END AS zscore,

        -- Absolute Z-score for threshold comparison
        CASE
            WHEN rolling_stddev_15 = 0 THEN 0
            WHEN window_size_15 < 5 THEN 0
            ELSE ABS((value - rolling_mean_15) / rolling_stddev_15)
        END AS abs_zscore

    FROM moving_averages ma
),


-- ============================================================
-- STEP 4: RESOLVE ALERT THRESHOLDS
-- ============================================================
-- Join each reading with the appropriate threshold rules.
-- Per-device thresholds override global defaults.
--
-- Strategy: Join on metric_type, use COALESCE logic — prefer
-- device-specific threshold, fall back to global (device_id IS NULL).
-- ============================================================

device_metric AS (
    -- Enrich readings with their device's metric type
    SELECT
        z.*,
        d.metric_type,
        d.device_name,
        d.location
    FROM zscore_calc z
    JOIN devices d ON z.device_id = d.device_id
),

resolved_thresholds AS (
    -- Find the matching severity for each reading's abs_zscore.
    -- Prefer per-device thresholds over global defaults.
    SELECT
        dm.*,
        t.severity AS alert_severity,
        t.min_zscore AS threshold_min,
        t.max_zscore AS threshold_max,
        -- Rank: per-device thresholds (device_id IS NOT NULL) win over globals;
        -- among equal precedence, higher min_zscore band breaks ties cleanly.
        ROW_NUMBER() OVER (
            PARTITION BY dm.reading_id
            ORDER BY
                CASE WHEN t.device_id IS NOT NULL THEN 0 ELSE 1 END ASC,
                t.min_zscore DESC
        ) AS threshold_priority
    FROM device_metric dm
    LEFT JOIN alert_thresholds t
        ON  t.metric_type = dm.metric_type
        AND (t.device_id = dm.device_id OR t.device_id IS NULL)
        AND dm.abs_zscore >= t.min_zscore
        AND (t.max_zscore IS NULL OR dm.abs_zscore < t.max_zscore)
),


-- ============================================================
-- STEP 5: FINAL ANOMALY CLASSIFICATION
-- ============================================================
-- Keep only the highest-priority (per-device > global) threshold
-- match for each reading. Readings with no threshold match are
-- normal (abs_zscore below all thresholds).
-- ============================================================

anomaly_flags AS (
    SELECT
        reading_id,
        device_id,
        device_name,
        location,
        metric_type,
        value,
        measured_at,
        ingested_at,
        ma_5,
        ma_15,
        ma_60,
        rolling_stddev_15,
        zscore,
        abs_zscore,
        alert_severity,
        threshold_min,
        threshold_max
    FROM resolved_thresholds
    WHERE threshold_priority = 1
)

-- ============================================================
-- FINAL OUTPUT: Analysis-Ready Dataset
-- ============================================================
-- Every deduplicated reading with its moving averages, Z-score,
-- and anomaly classification. NULL alert_severity = normal.
-- ============================================================

SELECT
    dm.reading_id,
    dm.device_id,
    dm.device_name,
    dm.location,
    dm.metric_type,
    dm.value,
    dm.measured_at,
    dm.ingested_at,

    -- Moving averages (rounded for readability)
    ROUND(dm.ma_5,  4)  AS ma_5,
    ROUND(dm.ma_15, 4)  AS ma_15,
    ROUND(dm.ma_60, 4)  AS ma_60,

    -- Statistical measures
    ROUND(dm.rolling_stddev_15, 4) AS rolling_stddev,
    ROUND(dm.zscore, 4)            AS zscore,
    ROUND(dm.abs_zscore, 4)        AS abs_zscore,

    -- Anomaly classification
    COALESCE(af.alert_severity, 'NORMAL') AS severity,

    -- Latency: how long after measurement did ingestion happen?
    -- (Useful for identifying late arrivals even after dedup)
    EXTRACT(EPOCH FROM (dm.ingested_at - dm.measured_at)) AS ingestion_latency_sec

FROM device_metric dm
LEFT JOIN anomaly_flags af
    ON dm.reading_id = af.reading_id

ORDER BY
    dm.device_id,
    dm.measured_at;


-- ============================================================
-- BONUS QUERY A: IDENTIFY REPORTING GAPS
-- ============================================================
-- Detect periods where a device stopped reporting for longer
-- than 5x its expected reporting interval.
-- ============================================================

/*
WITH clean_with_lag AS (
    SELECT
        cr.device_id,
        d.device_name,
        d.reporting_interval_sec,
        cr.measured_at,
        LAG(cr.measured_at) OVER (
            PARTITION BY cr.device_id
            ORDER BY cr.measured_at
        ) AS prev_measured_at
    FROM (
        -- Reuse dedup logic
        SELECT device_id, measured_at,
               ROW_NUMBER() OVER (
                   PARTITION BY device_id, measured_at, packet_seq
                   ORDER BY ingested_at ASC, reading_id ASC
               ) AS rn
        FROM sensor_readings
    ) cr
    JOIN devices d ON cr.device_id = d.device_id
    WHERE cr.rn = 1
)

SELECT
    device_id,
    device_name,
    prev_measured_at                              AS gap_start,
    measured_at                                   AS gap_end,
    EXTRACT(EPOCH FROM (measured_at - prev_measured_at)) AS gap_seconds,
    reporting_interval_sec * 5                    AS threshold_seconds
FROM clean_with_lag
WHERE prev_measured_at IS NOT NULL
  AND EXTRACT(EPOCH FROM (measured_at - prev_measured_at))
      > reporting_interval_sec * 5
ORDER BY device_id, gap_start;
*/


-- ============================================================
-- BONUS QUERY B: TREND DRIFT DETECTION
-- ============================================================
-- Compare MA_15 vs MA_60 to detect sustained drift.
-- When the ratio (MA_15 - MA_60) / MA_60 exceeds ±5%, flag it.
-- ============================================================

/*
SELECT
    device_id,
    device_name,
    measured_at,
    value,
    ROUND(ma_15, 4) AS ma_15,
    ROUND(ma_60, 4) AS ma_60,
    ROUND((ma_15 - ma_60) / NULLIF(ABS(ma_60), 0) * 100, 2) AS drift_pct,
    CASE
        WHEN (ma_15 - ma_60) / NULLIF(ABS(ma_60), 0) >  0.05 THEN 'UPWARD_DRIFT'
        WHEN (ma_15 - ma_60) / NULLIF(ABS(ma_60), 0) < -0.05 THEN 'DOWNWARD_DRIFT'
        ELSE 'STABLE'
    END AS drift_status
FROM (
    -- This subquery would use the same moving_averages CTE from above
    -- Shown standalone for demonstration
    SELECT
        sr.device_id,
        d.device_name,
        sr.measured_at,
        sr.value,
        AVG(sr.value) OVER (PARTITION BY sr.device_id ORDER BY sr.measured_at ROWS BETWEEN 14 PRECEDING AND CURRENT ROW) AS ma_15,
        AVG(sr.value) OVER (PARTITION BY sr.device_id ORDER BY sr.measured_at ROWS BETWEEN 59 PRECEDING AND CURRENT ROW) AS ma_60
    FROM sensor_readings sr
    JOIN devices d ON sr.device_id = d.device_id
) sub
WHERE ABS((ma_15 - ma_60) / NULLIF(ABS(ma_60), 0)) > 0.05
ORDER BY device_id, measured_at;
*/


-- ============================================================
-- BONUS QUERY C: ANOMALY EVENT CLUSTERING
-- ============================================================
-- Group consecutive anomalous readings into "events" using
-- a gaps-and-islands technique.
-- ============================================================

/*
WITH anomalous_readings AS (
    -- Assume this comes from the main query above
    -- Simplified: flag readings with abs_zscore >= 2.0
    SELECT
        device_id,
        measured_at,
        value,
        abs_zscore,
        severity,
        -- Assign a group ID using the islands technique:
        -- Subtract a row_number from a sequential counter to
        -- create matching group IDs for consecutive rows.
        ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY measured_at)
        - ROW_NUMBER() OVER (
            PARTITION BY device_id, (CASE WHEN abs_zscore >= 2.0 THEN 1 ELSE 0 END)
            ORDER BY measured_at
        ) AS island_id
    FROM final_output  -- reference to main query results
    WHERE abs_zscore >= 2.0
)

SELECT
    device_id,
    island_id,
    MIN(measured_at)                AS event_start,
    MAX(measured_at)                AS event_end,
    COUNT(*)                        AS readings_in_event,
    MAX(abs_zscore)                 AS peak_zscore,
    MAX(CASE WHEN severity = 'CRITICAL' THEN 1 ELSE 0 END) AS has_critical
FROM anomalous_readings
GROUP BY device_id, island_id
ORDER BY device_id, event_start;
*/
