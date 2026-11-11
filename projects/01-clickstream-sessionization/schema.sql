-- ============================================================================
-- Project 1: Clickstream Sessionization & Multi-Touch Attribution
-- Schema Definition (ANSI SQL DDL)
-- ============================================================================

-- --------------------------------------------------------------------------
-- Table: raw_clicks
-- Description: Raw clickstream events captured from website/mobile app.
--              Each row represents a single user interaction event.
-- --------------------------------------------------------------------------
CREATE TABLE raw_clicks (
    event_id        VARCHAR(36)     NOT NULL,   -- UUID for each event
    user_id         VARCHAR(36)     NOT NULL,   -- Anonymized user identifier
    event_timestamp TIMESTAMP       NOT NULL,   -- UTC timestamp of the event
    event_type      VARCHAR(20)     NOT NULL,   -- page_view, click, add_to_cart, purchase
    page_url        VARCHAR(500)    NOT NULL,   -- URL where the event occurred
    referrer_url    VARCHAR(500),               -- Referring URL (nullable)
    utm_source      VARCHAR(100),               -- UTM source parameter (nullable)
    utm_medium      VARCHAR(100),               -- UTM medium parameter (nullable)
    utm_campaign    VARCHAR(200),               -- UTM campaign parameter (nullable)
    device_type     VARCHAR(20),                -- desktop, mobile, tablet
    country_code    VARCHAR(2),                 -- ISO country code
    CONSTRAINT pk_raw_clicks PRIMARY KEY (event_id),
    CONSTRAINT chk_event_type CHECK (event_type IN ('page_view', 'click', 'add_to_cart', 'purchase'))
);

-- --------------------------------------------------------------------------
-- Table: page_views
-- Description: Enriched page view events extracted and processed from
--              raw_clicks. Contains page categorization and product mapping.
-- --------------------------------------------------------------------------
CREATE TABLE page_views (
    page_view_id    VARCHAR(36)     NOT NULL,   -- UUID for the page view record
    event_id        VARCHAR(36)     NOT NULL,   -- FK to raw_clicks.event_id
    user_id         VARCHAR(36)     NOT NULL,   -- Anonymized user identifier
    view_timestamp  TIMESTAMP       NOT NULL,   -- When the page was viewed
    page_url        VARCHAR(500)    NOT NULL,   -- URL of the page
    page_category   VARCHAR(50)     NOT NULL,   -- homepage, category, product, cart, checkout, other
    product_id      VARCHAR(36),                -- Product ID if on a product page (nullable)
    time_on_page_s  INTEGER,                    -- Estimated seconds spent on page (nullable)
    CONSTRAINT pk_page_views PRIMARY KEY (page_view_id),
    CONSTRAINT fk_pv_event FOREIGN KEY (event_id) REFERENCES raw_clicks(event_id)
);

-- --------------------------------------------------------------------------
-- Table: purchases
-- Description: Completed purchase transactions. Each row is one order
--              successfully placed by a user.
-- --------------------------------------------------------------------------
CREATE TABLE purchases (
    order_id        VARCHAR(36)     NOT NULL,   -- Unique order identifier
    user_id         VARCHAR(36)     NOT NULL,   -- User who made the purchase
    purchase_timestamp TIMESTAMP    NOT NULL,   -- UTC timestamp of the purchase
    revenue         DECIMAL(10, 2)  NOT NULL,   -- Order revenue in USD
    item_count      INTEGER         NOT NULL,   -- Number of items in the order
    CONSTRAINT pk_purchases PRIMARY KEY (order_id),
    CONSTRAINT chk_revenue CHECK (revenue >= 0),
    CONSTRAINT chk_item_count CHECK (item_count > 0)
);

-- --------------------------------------------------------------------------
-- Table: marketing_channels
-- Description: Reference/dimension table mapping UTM source+medium
--              combinations to canonical marketing channel names.
-- --------------------------------------------------------------------------
CREATE TABLE marketing_channels (
    channel_id      INTEGER         NOT NULL,   -- Surrogate key
    utm_source      VARCHAR(100)    NOT NULL,   -- UTM source value
    utm_medium      VARCHAR(100)    NOT NULL,   -- UTM medium value
    channel_name    VARCHAR(100)    NOT NULL,   -- Canonical channel name
    channel_group   VARCHAR(50)     NOT NULL,   -- High-level grouping (paid, organic, direct, etc.)
    CONSTRAINT pk_marketing_channels PRIMARY KEY (channel_id),
    CONSTRAINT uq_source_medium UNIQUE (utm_source, utm_medium)
);

-- --------------------------------------------------------------------------
-- Indexes for common query patterns
-- --------------------------------------------------------------------------
CREATE INDEX idx_raw_clicks_user_ts ON raw_clicks (user_id, event_timestamp);
CREATE INDEX idx_raw_clicks_utm ON raw_clicks (utm_source, utm_medium);
CREATE INDEX idx_page_views_user_ts ON page_views (user_id, view_timestamp);
CREATE INDEX idx_purchases_user_ts ON purchases (user_id, purchase_timestamp);
