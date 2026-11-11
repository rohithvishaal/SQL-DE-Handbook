-- ============================================================
-- Project 3: SaaS MRR Waterfall — Schema Definition
-- ============================================================
-- Dialect: ANSI SQL
-- Purpose: Store subscription lifecycle data for MRR waterfall
-- ============================================================

-- Plans: product tiers with monthly pricing
CREATE TABLE plans (
    plan_id        INT           PRIMARY KEY,
    plan_name      VARCHAR(100)  NOT NULL,
    monthly_price  DECIMAL(10,2) NOT NULL CHECK (monthly_price >= 0)
);

-- Subscriptions: each row is one subscription lifecycle
-- A customer who cancels and reactivates gets a new subscription row.
CREATE TABLE subscriptions (
    subscription_id  INT           PRIMARY KEY,
    customer_id      INT           NOT NULL,
    plan_id          INT           NOT NULL,
    started_at       DATE          NOT NULL,
    canceled_at      DATE,                        -- NULL = still active
    status           VARCHAR(20)   NOT NULL DEFAULT 'active'
                                   CHECK (status IN ('active', 'canceled')),
    CONSTRAINT fk_sub_plan FOREIGN KEY (plan_id) REFERENCES plans(plan_id)
);

-- Billing Events: append-only event log tracking every MRR movement
CREATE TABLE billing_events (
    event_id         INT           PRIMARY KEY,
    subscription_id  INT           NOT NULL,
    customer_id      INT           NOT NULL,
    event_type       VARCHAR(30)   NOT NULL
                                   CHECK (event_type IN (
                                       'new', 'upgrade', 'downgrade',
                                       'cancellation', 'reactivation'
                                   )),
    old_plan_id      INT,                         -- NULL for 'new' events
    new_plan_id      INT,                         -- NULL for 'cancellation' events
    old_mrr          DECIMAL(10,2) NOT NULL DEFAULT 0,
    new_mrr          DECIMAL(10,2) NOT NULL DEFAULT 0,
    event_date       DATE          NOT NULL,
    CONSTRAINT fk_event_sub  FOREIGN KEY (subscription_id) REFERENCES subscriptions(subscription_id),
    CONSTRAINT fk_event_old  FOREIGN KEY (old_plan_id)     REFERENCES plans(plan_id),
    CONSTRAINT fk_event_new  FOREIGN KEY (new_plan_id)     REFERENCES plans(plan_id)
);

-- Indexes for common query patterns
CREATE INDEX idx_billing_events_customer  ON billing_events(customer_id, event_date);
CREATE INDEX idx_billing_events_sub       ON billing_events(subscription_id, event_date);
CREATE INDEX idx_subscriptions_customer   ON subscriptions(customer_id, started_at);
