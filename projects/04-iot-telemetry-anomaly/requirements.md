# Project 4: IoT Telemetry Anomaly Detection

## Business Context

A large-scale IoT platform manages thousands of industrial sensors deployed across manufacturing facilities, data centers, and energy grids. These sensors emit temperature, humidity, pressure, and vibration readings every few seconds. The telemetry pipeline ingests millions of readings per hour into a central data warehouse.

Due to unreliable network conditions (cellular, LoRaWAN, satellite), the platform regularly encounters:

- **Duplicate packets** — the same reading retransmitted multiple times when acknowledgments are lost.
- **Late-arriving data** — readings that arrive minutes or hours after their actual measurement timestamp due to network buffering, device sleep cycles, or gateway store-and-forward behavior.
- **Noisy spikes** — legitimate but anomalous readings caused by equipment malfunction, environmental events, or sensor degradation.

The data engineering team must build a robust SQL pipeline that cleans, deduplicates, smooths, and flags anomalies in this telemetry stream — enabling downstream alerting dashboards and predictive maintenance models.

---

## Objectives

1. **Deduplicate late-arriving and retransmitted sensor packets** using deterministic, window-based deduplication that keeps only the earliest-ingested copy of each unique reading.
2. **Compute multi-scale rolling moving averages** (5-reading, 15-reading, and 60-reading windows) per device per metric to smooth noisy signals and reveal underlying trends.
3. **Detect statistical anomalies** by computing Z-scores against rolling windows — flag any reading whose Z-score exceeds device-specific or global thresholds.
4. **Classify anomaly severity** (INFO, WARNING, CRITICAL) based on configurable per-device alert thresholds.
5. **Produce a clean, analysis-ready dataset** that downstream dashboards and ML pipelines can consume directly.

---

## Input Schema Description

### `devices`
Master registry of all IoT devices. Each device has a unique identifier, a human-readable name, its physical location, the type of metric it measures, and its installation date. Devices may be active or decommissioned.

### `sensor_readings`
Raw telemetry ingestion table. Each row represents a single sensor reading with:
- A unique reading ID
- The device that produced it
- The measured value (floating point)
- The **measurement timestamp** (when the sensor actually took the reading)
- The **ingested timestamp** (when the platform received and stored it)
- A packet sequence number assigned by the device firmware (used for dedup)

Duplicate rows will share the same `device_id`, `measured_at`, and `packet_seq` but may have different `ingested_at` timestamps.

### `alert_thresholds`
Configurable per-device (or global default) thresholds that define the Z-score boundaries for each severity level (INFO, WARNING, CRITICAL). Allows operators to tune sensitivity per device without code changes.

---

## Expected Deliverables

1. **`schema.sql`** — DDL statements creating all three tables with appropriate data types, constraints, and indexes.
2. **`seed_data.sql`** — Realistic mock data including:
   - Multiple devices across different locations and metric types
   - Duplicate packets (same device + timestamp + packet_seq, different ingestion times)
   - Late arrivals (large gap between `measured_at` and `ingested_at`)
   - Normal readings with natural variance
   - Anomalous spikes (readings 3-5+ standard deviations from the mean)
3. **`solution.sql`** — Complete reference solution containing:
   - CTE-based deduplication step
   - Multi-scale moving average computation
   - Z-score anomaly detection
   - Severity classification using alert thresholds
   - Final clean output query

---

## Bonus Challenges

1. **Gap Detection** — Identify periods where a device stopped reporting (gaps > 5× the expected reporting interval) and flag them as potential device failures.
2. **Trend Drift Detection** — Compare the 15-reading moving average against the 60-reading moving average to detect sustained upward or downward drift in sensor values.
3. **Anomaly Clustering** — Group consecutive anomalous readings into "anomaly events" with a start time, end time, peak deviation, and duration.
4. **Device Health Score** — Compute a per-device health score based on anomaly frequency, gap frequency, and reading regularity over the trailing 24 hours.
5. **Cross-Device Correlation** — For devices at the same location, detect when multiple devices flag anomalies within a short time window (potential environmental event vs. single device malfunction).
