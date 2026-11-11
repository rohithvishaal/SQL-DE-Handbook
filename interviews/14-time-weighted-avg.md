# Time-Weighted Averages for IoT / Sensor Data

## Difficulty

🔴 **Hard**

## Companies

Tesla, Honeywell, Samsara, Uptake, Rivian, Amazon (AWS IoT)

---

## Problem Statement

You are a Data Engineer on a fleet telemetry / smart-factory IoT platform. Industrial temperature sensors emit readings **only when the value changes significantly** (event-driven / change-of-value reporting) rather than on a fixed 1-second tick. As a result, timestamps between consecutive readings are **irregular**.

If a thermostat sits at `20.0°C` for 50 minutes and spikes to `80.0°C` for the last 10 minutes of an hour (emitting 5 rapid readings during that spike: `80, 81, 79, 80, 80`), a naive `AVG(temperature)` over those 6 rows gives `~70°C` — wildly skewed because high-frequency burst points dominate!

The engineering team needs the **true Time-Weighted Average (TWA)** temperature per sensor over a given reporting window (`2025-03-01 10:00:00` to `2025-03-01 11:00:00`), using **step-function (zero-order hold)** interpolation: each reading remains valid from its timestamp until the next reading (or the end of the reporting window). Also note: a reading recorded *before* `10:00:00` carries forward as the active state at `10:00:00`!

---

## Schema DDL

```sql
CREATE TABLE sensor_readings (
    reading_id    BIGINT PRIMARY KEY,
    sensor_id     VARCHAR(20)   NOT NULL,
    recorded_at   TIMESTAMP     NOT NULL,
    temperature   DECIMAL(6, 2) NOT NULL
);

INSERT INTO sensor_readings (reading_id, sensor_id, recorded_at, temperature) VALUES
-- Sensor S1: Carry-over reading at 09:45 (20.0°C) holds from 10:00 to 10:50 (50 mins = 3000s),
-- then bursts around 80°C for the last 10 minutes (600s).
(1,  'S1', '2025-03-01 09:45:00', 20.00),
(2,  'S1', '2025-03-01 10:50:00', 80.00),
(3,  'S1', '2025-03-01 10:52:00', 81.00),
(4,  'S1', '2025-03-01 10:54:00', 79.00),
(5,  'S1', '2025-03-01 10:56:00', 80.00),
(6,  'S1', '2025-03-01 10:58:00', 80.00),
-- Reading after window close (should NOT be counted inside [10:00, 11:00), though tells us S1 stayed 80 until 11:00)
(7,  'S1', '2025-03-01 11:10:00', 25.00),

-- Sensor S2: First reading starts inside window at 10:15 (no prior reading before 10:00)
-- Holds 30.0°C from 10:15 to 10:45 (30 mins = 1800s), then 45.0°C from 10:45 to 11:00 (15 mins = 900s).
(8,  'S2', '2025-03-01 10:15:00', 30.00),
(9,  'S2', '2025-03-01 10:45:00', 45.00),

-- Sensor S3: Only a single carry-over reading before window (09:30 -> 55.0°C), none inside window
(10, 'S3', '2025-03-01 09:30:00', 55.00);
```

---

## Sample Input

**sensor_readings** (Reporting Window: `2025-03-01 10:00:00` to `2025-03-01 11:00:00`)

| reading_id | sensor_id | recorded_at         | temperature |
|------------|-----------|---------------------|-------------|
| 1          | S1        | 2025-03-01 09:45:00 | 20.00       |
| 2          | S1        | 2025-03-01 10:50:00 | 80.00       |
| 3          | S1        | 2025-03-01 10:52:00 | 81.00       |
| 4          | S1        | 2025-03-01 10:54:00 | 79.00       |
| 5          | S1        | 2025-03-01 10:56:00 | 80.00       |
| 6          | S1        | 2025-03-01 10:58:00 | 80.00       |
| 7          | S1        | 2025-03-01 11:10:00 | 25.00       |
| 8          | S2        | 2025-03-01 10:15:00 | 30.00       |
| 9          | S2        | 2025-03-01 10:45:00 | 45.00       |
| 10         | S3        | 2025-03-01 09:30:00 | 55.00       |

---

## Expected Output

| sensor_id | naive_avg | time_weighted_avg | covered_seconds |
|-----------|-----------|-------------------|-----------------|
| S1        | 80.00     | 30.00             | 3600            |
| S2        | 37.50     | 35.00             | 2700            |
| S3        | NULL      | 55.00             | 3600            |

> [!NOTE]
> Let's verify the math for each sensor over `[10:00, 11:00)`:
> - **S1**: `20.00` (from `09:45`, clipped to `10:00..10:50` = 3000s) + `80.00` (120s) + `81.00` (120s) + `79.00` (120s) + `80.00` (120s) + `80.00` (120s) = `(20*3000 + 80*120 + 81*120 + 79*120 + 80*120 + 80*120) / 3600` = `(60000 + 48000) / 3600` = `108000 / 3600` = **`30.00`**! Notice naive `AVG` inside `[10:00, 11:00)` was `(80+81+79+80+80)/5 = 80.00`!
> - **S2**: `30.00` (`10:15..10:45` = 1800s) + `45.00` (`10:45..11:00` = 900s) = `(30*1800 + 45*900) / 2700` = `94500 / 2700` = **`35.00`**.
> - **S3**: Carry-over reading at `09:30` holds `55.00` across the entire `[10:00, 11:00)` window (3600s) = **`55.00`**, even though zero readings fired inside the hour!

---

## Brute Force Solution

**Approach: Expand readings onto a 1-second (or 1-minute) time spine using `GENERATE_SERIES` + `ASOF` / range lookup**

A common brute-force intuition is to generate every second in `[10:00:00, 11:00:00)`, look up the most recent reading at or before each second, and take a simple `AVG()`.

```sql
WITH RECURSIVE seconds_spine AS (
    SELECT TIMESTAMP '2025-03-01 10:00:00' AS tick
    UNION ALL
    SELECT tick + INTERVAL '1' MINUTE -- (1-minute grain; 1-second would generate 3600 rows/sensor!)
    FROM seconds_spine
    WHERE tick + INTERVAL '1' MINUTE < TIMESTAMP '2025-03-01 11:00:00'
),
sensors AS (
    SELECT DISTINCT sensor_id FROM sensor_readings
),
grid AS (
    SELECT s.sensor_id, sp.tick
    FROM sensors s
    CROSS JOIN seconds_spine sp
),
mapped AS (
    SELECT
        g.sensor_id,
        g.tick,
        (
            SELECT r.temperature
            FROM sensor_readings r
            WHERE r.sensor_id = g.sensor_id
              AND r.recorded_at <= g.tick
            ORDER BY r.recorded_at DESC, r.reading_id DESC
            LIMIT 1
        ) AS temp_at_tick
    FROM grid g
)
SELECT
    sensor_id,
    ROUND(AVG(temp_at_tick), 2) AS approx_time_weighted_avg
FROM mapped
WHERE temp_at_tick IS NOT NULL
GROUP BY sensor_id
ORDER BY sensor_id;
```

**Explanation:**
1. Generate a regular grid of timestamps across the window for every sensor.
2. At each grid point, run a correlated subquery to find the active reading (`MAX(recorded_at) <= tick`).
3. Average the grid points.

**Drawbacks:**
- **Severe approximation error**: Using 1-minute ticks fails completely when sensor bursts happen at sub-minute precision (e.g., every 5 seconds). Using 1-second ticks blows up row volume by **3,600x per hour** (or 86,400x per day per sensor!).
- **O(N_sensors × N_ticks × N_readings)** complexity with the correlated `ORDER BY ... LIMIT 1` lookup.
- Completely unnecessary memory/CPU cost when each step interval is constant!

---

## Optimal Solution

**Approach: `LEAD()` interval clipping + exact analytical duration weighting**

Instead of discretizing time into ticks, compute the exact `[start_ts, end_ts)` interval for every reading using `LEAD(recorded_at)`, **clip** each interval to `[window_start, window_end)`, and compute $\frac{\sum (\text{temperature}_i \times \text{duration}_i)}{\sum \text{duration}_i}$.

```sql
WITH bounds AS (
    SELECT
        TIMESTAMP '2025-03-01 10:00:00' AS win_start,
        TIMESTAMP '2025-03-01 11:00:00' AS win_end
),
-- Compute each reading's natural validity interval [recorded_at, next_recorded_at)
intervals AS (
    SELECT
        r.sensor_id,
        r.recorded_at AS raw_start,
        COALESCE(
            LEAD(r.recorded_at) OVER (
                PARTITION BY r.sensor_id
                ORDER BY r.recorded_at, r.reading_id
            ),
            b.win_end
        ) AS raw_end,
        r.temperature,
        b.win_start,
        b.win_end
    FROM sensor_readings r
    CROSS JOIN bounds b
    -- Optimization: drop readings that start at or after window end
    WHERE r.recorded_at < b.win_end
),
-- Clip intervals to [win_start, win_end) and drop intervals ending before win_start
clipped AS (
    SELECT
        sensor_id,
        temperature,
        raw_start,
        CASE WHEN raw_start > win_start THEN raw_start ELSE win_start END AS eff_start,
        CASE WHEN raw_end   < win_end   THEN raw_end   ELSE win_end   END AS eff_end,
        win_start,
        win_end
    FROM intervals
    WHERE raw_end > win_start
),
durations AS (
    SELECT
        sensor_id,
        temperature,
        raw_start,
        win_start,
        -- ANSI/Postgres duration in seconds; in BigQuery use TIMESTAMP_DIFF, Snowflake DATEDIFF('second', ...)
        EXTRACT(EPOCH FROM (eff_end - eff_start)) AS duration_sec
    FROM clipped
    WHERE eff_end > eff_start
)
SELECT
    sensor_id,
    ROUND(
        AVG(CASE WHEN raw_start >= win_start THEN temperature END),
        2
    ) AS naive_avg,
    ROUND(
        SUM(temperature * duration_sec) / NULLIF(SUM(duration_sec), 0),
        2
    ) AS time_weighted_avg,
    CAST(SUM(duration_sec) AS INT) AS covered_seconds
FROM durations
GROUP BY sensor_id
ORDER BY sensor_id;
```

### Why This Is Better

| Dimension | Brute Force (Time Spine) | Optimal (`LEAD` + Interval Clipping) |
|-----------|--------------------------|--------------------------------------|
| **Precision** | Approximate (depends on tick size) | **Mathematically exact** to sub-second precision |
| **Row amplification** | $3{,}600\times$ (at 1s grain) or $86{,}400\times$/day | **$1\times$** (no row explosion at all) |
| **Complexity** | $O(S \cdot T \cdot R)$ | **$O(R \log R)$** single window sort |
| **Carry-over state** | Requires expensive `ORDER BY LIMIT 1` | Handled naturally by clipping `[raw_start, raw_end)` to `win_start` |

> [!WARNING]
> **Critical Edge Case — Duplicate Timestamps**: If two readings for the same sensor arrive with the exact same `recorded_at`, the first reading gets `eff_end - eff_start = 0` seconds (`duration_sec = 0`), while the second reading gets the real duration. Filtering `WHERE eff_end > eff_start` drops zero-duration rows cleanly. Always include `reading_id` in `ORDER BY recorded_at, reading_id` so the latest reading deterministically takes the duration!

---

## Interviewer Follow-Up Questions

### 1. "How do you make sure you don't scan 5 years of history before `win_start` just to find the one carry-over reading?"

If you just filter `WHERE recorded_at < win_end`, the query could scan years of old partitions! To prune partitions safely:
1. Apply a reasonable **lookback bound** based on sensor heartbeat SLA (e.g., `WHERE recorded_at >= win_start - INTERVAL '24' HOUR`), OR
2. Run two fast indexed lookups combined with `UNION ALL`:
   - All readings inside `[win_start, win_end)`, **plus**
   - The single latest reading before `win_start` per sensor (`ROW_NUMBER() OVER (PARTITION BY sensor_id ORDER BY recorded_at DESC) = 1` where `recorded_at < win_start`).

### 2. "What if the business wants linear interpolation (trapezoidal rule) instead of step-function (zero-order hold)?"

In the trapezoidal rule, the temperature transitions smoothly from `temp_i` to `temp_{i+1}`. The weighted contribution for segment `[eff_start, eff_end)` is simply the average of the start and end values multiplied by duration:
```sql
SUM(((temp_at_eff_start + temp_at_eff_end) / 2.0) * duration_sec) / SUM(duration_sec)
```
Note that if a segment crosses `win_start` or `win_end`, you must linearly interpolate the boundary temperature at `win_start` / `win_end` before taking the trapezoid average!

### 3. "What if a sensor drops offline and shouldn't be assumed constant forever (e.g., max hold time = 30 minutes)?"

Cap `raw_end` using `LEAST(next_recorded_at, raw_start + INTERVAL '30' MINUTE, win_end)`. That way, any gap longer than 30 minutes stops accumulating weight after 30 minutes, and `covered_seconds` immediately reveals sensor downtime / data coverage!

---

## Key Takeaways

- 📌 **Never average raw event-driven IoT readings** — bursts bias `AVG()` heavily toward volatile periods
- 📌 **`LEAD(recorded_at) OVER (PARTITION BY sensor_id ORDER BY recorded_at)`** turns point events into half-open intervals `[start, end)` in $O(N \log N)$ without row explosion
- 📌 **Interval clipping** (`GREATEST(raw_start, win_start)` and `LEAST(raw_end, win_end)`) cleanly incorporates pre-window carry-over values (`S1`, `S3`) and respects window boundaries (`S1` row 7)
- 📌 Always return **`covered_seconds`** alongside `time_weighted_avg` so downstream consumers can detect partial coverage (`S2`: 2700s / 3600s) or offline sensors
- 📌 Guard `SUM(duration_sec)` with `NULLIF(..., 0)` to prevent division-by-zero on single-instant duplicate timestamps
