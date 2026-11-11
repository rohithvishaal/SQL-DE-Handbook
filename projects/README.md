# Real-Life Data Engineering SQL Capstone Projects

Welcome to the **Capstone Projects** section of the Data Engineering SQL Handbook. Each project simulates an end-to-end production data engineering scenario — complete with business requirements, ANSI SQL schemas, realistic edge-case seed data, and heavily commented reference solutions built with modular CTEs.

## Project Directory Structure

Every project lives in its own folder and contains four standardized files:

| File | Purpose |
| :--- | :--- |
| `requirements.md` | Business context, numbered objectives, input schema description, deliverables, and bonus challenges |
| `schema.sql` | Dialect-agnostic ANSI SQL DDL (`CREATE TABLE`, constraints, foreign keys, indexes) |
| `seed_data.sql` | Realistic mock datasets engineered to trigger production edge cases (30–60+ rows per main table) |
| `solution.sql` | Heavily commented, step-by-step reference pipeline using modular CTEs and reconciliation checks |

---

## Capstone Projects Index

| # | Project | Difficulty | Skills Practiced | Est. Time | Directory |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **01** | **Clickstream Sessionization & Multi-Touch Attribution** | Intermediate | `LAG()`, cumulative `SUM()` sessionization, window frames, funnel metrics, First-Touch / Last-Touch / Linear attribution, revenue reconciliation | 2–3 hrs | [`01-clickstream-sessionization/`](./01-clickstream-sessionization/requirements.md) |
| **02** | **FinTech SCD2 Ledger & Reconciliation** | Advanced | `MERGE INTO` SCD Type 2, `valid_from`/`valid_to`/`is_current` history chains, out-of-order/late postings, point-in-time queries, idempotency, EOD balance reconciliation | 3–4 hrs | [`02-fintech-scd2-ledger/`](./02-fintech-scd2-ledger/requirements.md) |
| **03** | **SaaS MRR Waterfall Analysis** | Intermediate–Advanced | Recursive/calendar month spines, snapshot expansion, `LAG()`/`LEAD()` MoM deltas, MRR movement classification (New, Expansion, Contraction, Churn, Reactivation), waterfall reconciliation | 2.5–3.5 hrs | [`03-saas-mrr-waterfall/`](./03-saas-mrr-waterfall/requirements.md) |
| **04** | **IoT Telemetry Anomaly Detection** | Advanced | Deterministic `ROW_NUMBER()` deduplication of late/duplicate packets, multi-scale rolling moving averages (`ROWS BETWEEN`), rolling standard deviation, Z-score anomaly flagging, threshold joins | 3–4 hrs | [`04-iot-telemetry-anomaly/`](./04-iot-telemetry-anomaly/requirements.md) |

---

## Project Overviews

### 1. [Clickstream Sessionization & Multi-Touch Attribution](./01-clickstream-sessionization/requirements.md)
- **Difficulty**: Intermediate | **Estimated Time**: 2–3 hours
- **Business Scenario**: An e-commerce platform ("ShopStream") logs unstructured clickstream events without native session identifiers. Reconstruct 30-minute idle-timeout sessions, compute engagement and conversion metrics, and attribute purchase revenue across marketing channels.
- **Core Tables**: `raw_clicks`, `page_views`, `purchases`, `marketing_channels`
- **Edge Cases Covered**: Single-event bounces, multi-channel sessions, repeat purchases resetting attribution windows, tied timestamps.
- **Files**: [`requirements.md`](./01-clickstream-sessionization/requirements.md) | [`schema.sql`](./01-clickstream-sessionization/schema.sql) | [`seed_data.sql`](./01-clickstream-sessionization/seed_data.sql) | [`solution.sql`](./01-clickstream-sessionization/solution.sql)

### 2. [FinTech SCD2 Ledger — Account Balance Tracking](./02-fintech-scd2-ledger/requirements.md)
- **Difficulty**: Advanced | **Estimated Time**: 3–4 hours
- **Business Scenario**: A digital wallet platform requires an immutable, compliance-grade audit trail of every account balance change. Settlement feeds arrive out of chronological order (`transaction_date` vs. `posted_date`), requiring retroactive history updates and strict EOD balance reconciliation.
- **Core Tables**: `accounts`, `transactions`, `account_history`
- **Edge Cases Covered**: Out-of-order late settlements, retroactive history window splicing, point-in-time balance reconstruction, duplicate-batch idempotency, balance discrepancy detection.
- **Files**: [`requirements.md`](./02-fintech-scd2-ledger/requirements.md) | [`schema.sql`](./02-fintech-scd2-ledger/schema.sql) | [`seed_data.sql`](./02-fintech-scd2-ledger/seed_data.sql) | [`solution.sql`](./02-fintech-scd2-ledger/solution.sql)

### 3. [SaaS MRR Waterfall Analysis](./03-saas-mrr-waterfall/requirements.md)
- **Difficulty**: Intermediate–Advanced | **Estimated Time**: 2.5–3.5 hours
- **Business Scenario**: A B2B SaaS company ("CloudSync") needs a board-ready Monthly Recurring Revenue waterfall reconciling `Beginning MRR + New + Expansion − Contraction − Churn + Reactivation = Ending MRR` across customer upgrades, downgrades, cancellations, and reactivations.
- **Core Tables**: `plans`, `subscriptions`, `billing_events`
- **Edge Cases Covered**: Multi-month active gaps, same-month upgrades/downgrades, churn followed by reactivation in a later month, zero-variance waterfall balancing.
- **Files**: [`requirements.md`](./03-saas-mrr-waterfall/requirements.md) | [`schema.sql`](./03-saas-mrr-waterfall/schema.sql) | [`seed_data.sql`](./03-saas-mrr-waterfall/seed_data.sql) | [`solution.sql`](./03-saas-mrr-waterfall/solution.sql)

### 4. [IoT Telemetry Anomaly Detection](./04-iot-telemetry-anomaly/requirements.md)
- **Difficulty**: Advanced | **Estimated Time**: 3–4 hours
- **Business Scenario**: An industrial IoT platform ingests noisy sensor telemetry over unreliable networks. Clean retransmitted and late-arriving packets, compute multi-scale rolling moving averages (5-, 15-, and 60-reading windows), and flag statistical Z-score anomalies with configurable severity thresholds (`INFO`, `WARNING`, `CRITICAL`).
- **Core Tables**: `devices`, `sensor_readings`, `alert_thresholds`
- **Edge Cases Covered**: Duplicate packets with varying `ingested_at` timestamps, late-arriving buffered payloads, multi-window `ROWS BETWEEN` smoothing, per-device vs. global fallback thresholds.
- **Files**: [`requirements.md`](./04-iot-telemetry-anomaly/requirements.md) | [`schema.sql`](./04-iot-telemetry-anomaly/schema.sql) | [`seed_data.sql`](./04-iot-telemetry-anomaly/seed_data.sql) | [`solution.sql`](./04-iot-telemetry-anomaly/solution.sql)

---

## How to Practice Locally

1. **Read `requirements.md` first** — avoid peeking at `solution.sql` until you have designed your own CTE flow.
2. **Load the schema and seed data** into a local SQL engine such as **DuckDB** or **PostgreSQL**:
   ```bash
   # Example with DuckDB CLI
   duckdb project_01.duckdb < projects/01-clickstream-sessionization/schema.sql
   duckdb project_01.duckdb < projects/01-clickstream-sessionization/seed_data.sql
   duckdb project_01.duckdb < projects/01-clickstream-sessionization/solution.sql
   ```
3. **Compare and extend** — verify your outputs against the reconciliation checks in `solution.sql`, then tackle the **Bonus Challenges** listed in each project's `requirements.md`.

> [!TIP]
> All schemas and solutions follow **ANSI SQL** conventions, with inline comments noting minor syntax adjustments for Snowflake, BigQuery, Databricks Spark SQL, DuckDB, and PostgreSQL.
