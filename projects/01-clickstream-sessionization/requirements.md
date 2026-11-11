# Project 1: Clickstream Sessionization & Multi-Touch Attribution

## Business Context

An e-commerce company ("ShopStream") captures raw clickstream events from its website and mobile app. Every page view, button click, product interaction, and purchase is logged as a JSON event with a timestamp, user identifier, and metadata. However, the raw event stream is **unstructured** — there is no concept of a "session" in the raw data.

The marketing team needs to understand how users navigate the site, which marketing channels drive revenue, and how to attribute conversions across multiple touchpoints. The data engineering team is tasked with building a pipeline that reconstructs user sessions from raw events, computes session-level metrics, and performs multi-touch attribution across marketing channels.

Currently, analysts manually export data to spreadsheets for ad-hoc analysis, leading to inconsistent session definitions and conflicting attribution numbers across teams. This project will establish a **single source of truth** for session analytics and channel attribution.

## Objectives

1. **Ingest & Normalize**: Parse raw clickstream events into a structured, queryable format with consistent data types and naming conventions.
2. **Session Reconstruction**: Implement 30-minute idle-timeout sessionization — if a user has no activity for 30+ minutes, subsequent events belong to a new session.
3. **Session Metrics**: Compute key session-level metrics including session duration, page count, bounce rate indicator, and conversion flag.
4. **Multi-Touch Attribution**: Implement three attribution models to distribute purchase revenue across marketing channels:
   - **First-Touch Attribution**: 100% credit to the first marketing channel in the conversion path.
   - **Last-Touch Attribution**: 100% credit to the last marketing channel before conversion.
   - **Linear Attribution**: Equal credit distributed across all distinct channels in the conversion path.
5. **Channel Performance Report**: Produce a summary report showing attributed revenue per channel under each model.

## Input Schema Description

| Table | Description |
|-------|-------------|
| `raw_clicks` | Raw clickstream events with user ID, timestamp, event type, page URL, referrer, and UTM parameters. Each row is a single user interaction. |
| `page_views` | Enriched page view events extracted from raw clicks, with page category, product ID (if applicable), and time-on-page estimate. |
| `purchases` | Completed purchase transactions with order ID, user ID, timestamp, and revenue amount. |
| `marketing_channels` | Reference/dimension table mapping UTM source/medium combinations to canonical marketing channel names (e.g., "google/cpc" → "Paid Search"). |

### Key Columns

- `raw_clicks.event_id` — Unique event identifier (UUID)
- `raw_clicks.user_id` — Anonymized user identifier
- `raw_clicks.event_timestamp` — UTC timestamp of the event
- `raw_clicks.event_type` — Type of interaction: `page_view`, `click`, `add_to_cart`, `purchase`
- `raw_clicks.page_url` — URL of the page where the event occurred
- `raw_clicks.utm_source` / `utm_medium` / `utm_campaign` — Marketing attribution parameters (nullable)
- `purchases.order_id` — Unique order identifier
- `purchases.revenue` — Order revenue in USD

## Expected Deliverables

1. **`schema.sql`** — DDL statements creating all four tables with appropriate data types, constraints, and indexes.
2. **`seed_data.sql`** — Realistic mock data covering multiple users, sessions, channels, and purchases (50+ rows across tables).
3. **`solution.sql`** — Complete SQL solution with the following clearly separated steps:
   - **Step 1**: Session boundary detection using `LAG()` and cumulative `SUM()` to assign session IDs.
   - **Step 2**: Session-level metric aggregation (duration, page count, bounce flag, conversion flag).
   - **Step 3**: Building the conversion path — ordered list of marketing channels touched before each purchase.
   - **Step 4**: First-touch, last-touch, and linear attribution calculations.
   - **Step 5**: Channel performance summary report.

## Bonus Challenges

1. **Cross-Device Sessionization**: Extend the solution to handle users who switch between devices (e.g., mobile → desktop) using a `device_id` column alongside `user_id`.
2. **Time-Decay Attribution**: Implement a time-decay model where channels closer to the conversion event receive exponentially more credit.
3. **Bounce Rate Analysis**: Compute bounce rate by channel — what percentage of sessions from each channel are single-page visits?
4. **Session Funnel Analysis**: Track conversion funnel stages (landing → product view → add to cart → purchase) and compute drop-off rates per stage.
5. **Real-Time vs. Batch**: Discuss how this pipeline would differ if implemented as a streaming pipeline (e.g., Apache Flink SQL) vs. batch (e.g., dbt + Snowflake).
