-- ============================================================
-- Project 4: IoT Telemetry Anomaly Detection — Schema
-- ============================================================
-- Dialect: ANSI SQL (portable across PostgreSQL, Snowflake,
--          BigQuery, DuckDB with minor type adjustments)
-- ============================================================

-- ------------------------------------------------------------
-- 1. devices — Master registry of IoT sensor devices
-- ------------------------------------------------------------
CREATE TABLE devices (
    device_id       INT           PRIMARY KEY,
    device_name     VARCHAR(100)  NOT NULL,
    location        VARCHAR(200)  NOT NULL,
    metric_type     VARCHAR(50)   NOT NULL,       -- e.g. 'temperature_c', 'humidity_pct', 'pressure_hpa', 'vibration_mm_s'
    reporting_interval_sec INT    NOT NULL DEFAULT 30,  -- expected seconds between readings
    status          VARCHAR(20)   NOT NULL DEFAULT 'active',  -- 'active' | 'decommissioned'
    installed_at    TIMESTAMP     NOT NULL,
    decommissioned_at TIMESTAMP  NULL
);

-- ------------------------------------------------------------
-- 2. sensor_readings — Raw telemetry ingestion table
-- ------------------------------------------------------------
-- Duplicates are expected: same (device_id, measured_at, packet_seq)
-- may appear multiple times with different ingested_at values.
-- ------------------------------------------------------------
CREATE TABLE sensor_readings (
    reading_id      INT           PRIMARY KEY,
    device_id       INT           NOT NULL REFERENCES devices(device_id),
    value           DECIMAL(12,4) NOT NULL,
    measured_at     TIMESTAMP     NOT NULL,       -- actual sensor measurement time
    ingested_at     TIMESTAMP     NOT NULL,       -- warehouse arrival time
    packet_seq      INT           NOT NULL        -- firmware-assigned sequence number
);

-- Index to accelerate deduplication and time-series queries
CREATE INDEX idx_readings_device_measured
    ON sensor_readings (device_id, measured_at);

CREATE INDEX idx_readings_dedup
    ON sensor_readings (device_id, packet_seq, measured_at, ingested_at);

-- ------------------------------------------------------------
-- 3. alert_thresholds — Configurable anomaly detection thresholds
-- ------------------------------------------------------------
-- device_id = NULL means "global default" for that metric_type.
-- Per-device rows override the global default.
-- ------------------------------------------------------------
CREATE TABLE alert_thresholds (
    threshold_id    INT           PRIMARY KEY,
    device_id       INT           NULL REFERENCES devices(device_id),  -- NULL = global default
    metric_type     VARCHAR(50)   NOT NULL,
    severity        VARCHAR(20)   NOT NULL,       -- 'INFO' | 'WARNING' | 'CRITICAL'
    min_zscore      DECIMAL(5,2)  NOT NULL,       -- absolute Z-score lower bound (inclusive)
    max_zscore      DECIMAL(5,2)  NULL,           -- absolute Z-score upper bound (exclusive), NULL = unbounded
    CONSTRAINT chk_severity CHECK (severity IN ('INFO', 'WARNING', 'CRITICAL'))
);

CREATE INDEX idx_thresholds_lookup
    ON alert_thresholds (metric_type, device_id);
