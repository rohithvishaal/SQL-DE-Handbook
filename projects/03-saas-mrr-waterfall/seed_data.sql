-- ============================================================
-- Project 3: SaaS MRR Waterfall — Seed Data
-- ============================================================
-- Coverage period: 2024-01 through 2024-08
-- 5 plans, 20 customers, 30+ subscriptions, 50+ billing events
-- Edge cases: upgrades, downgrades, cancellations, reactivations,
--             mid-month changes, same-month churn & reactivation
-- ============================================================

-- ----------------------------------------
-- Plans (5 tiers)
-- ----------------------------------------
INSERT INTO plans (plan_id, plan_name, monthly_price) VALUES (1, 'Starter',    29.00);
INSERT INTO plans (plan_id, plan_name, monthly_price) VALUES (2, 'Growth',     79.00);
INSERT INTO plans (plan_id, plan_name, monthly_price) VALUES (3, 'Pro',       149.00);
INSERT INTO plans (plan_id, plan_name, monthly_price) VALUES (4, 'Business',  299.00);
INSERT INTO plans (plan_id, plan_name, monthly_price) VALUES (5, 'Enterprise', 599.00);

-- ----------------------------------------
-- Subscriptions (36 rows)
-- A customer may have multiple rows if they cancel then reactivate.
-- ----------------------------------------

-- Customer 101: Starter since Jan, upgrades in Mar
INSERT INTO subscriptions VALUES (1,  101, 2, '2024-01-10', NULL,         'active');

-- Customer 102: Growth since Jan, downgrades in Apr, cancels in Jun
INSERT INTO subscriptions VALUES (2,  102, 1, '2024-01-15', '2024-06-01', 'canceled');

-- Customer 103: Pro since Jan, stable (no changes)
INSERT INTO subscriptions VALUES (3,  103, 3, '2024-01-05', NULL,         'active');

-- Customer 104: Starter since Feb, cancels in Apr, reactivates Jun on Growth
INSERT INTO subscriptions VALUES (4,  104, 1, '2024-02-01', '2024-04-15', 'canceled');
INSERT INTO subscriptions VALUES (5,  104, 2, '2024-06-01', NULL,         'active');

-- Customer 105: Business since Jan, upgrades to Enterprise in May
INSERT INTO subscriptions VALUES (6,  105, 5, '2024-01-20', NULL,         'active');

-- Customer 106: Growth since Feb, cancels in Mar (quick churn)
INSERT INTO subscriptions VALUES (7,  106, 2, '2024-02-10', '2024-03-15', 'canceled');

-- Customer 107: Pro since Mar, downgrades to Growth in Jun
INSERT INTO subscriptions VALUES (8,  107, 2, '2024-03-01', NULL,         'active');

-- Customer 108: Starter since Jan, upgrades to Growth in Feb, to Pro in May
INSERT INTO subscriptions VALUES (9,  108, 3, '2024-01-12', NULL,         'active');

-- Customer 109: Enterprise since Feb, stable
INSERT INTO subscriptions VALUES (10, 109, 5, '2024-02-01', NULL,         'active');

-- Customer 110: Growth since Mar, cancels Jul
INSERT INTO subscriptions VALUES (11, 110, 2, '2024-03-15', '2024-07-01', 'canceled');

-- Customer 111: Starter since Jan, cancels Feb, reactivates Apr on Starter, upgrades Jul
INSERT INTO subscriptions VALUES (12, 111, 1, '2024-01-08', '2024-02-10', 'canceled');
INSERT INTO subscriptions VALUES (13, 111, 2, '2024-04-01', NULL,         'active');

-- Customer 112: Pro since Apr
INSERT INTO subscriptions VALUES (14, 112, 3, '2024-04-05', NULL,         'active');

-- Customer 113: Business since Jan, downgrades to Pro in Mar, cancels in Jul
INSERT INTO subscriptions VALUES (15, 113, 3, '2024-01-18', '2024-07-15', 'canceled');

-- Customer 114: Growth since May
INSERT INTO subscriptions VALUES (16, 114, 2, '2024-05-01', NULL,         'active');

-- Customer 115: Starter since Feb, upgrades to Business in Jun
INSERT INTO subscriptions VALUES (17, 115, 4, '2024-02-20', NULL,         'active');

-- Customer 116: Enterprise since Mar, downgrades to Business in Jul
INSERT INTO subscriptions VALUES (18, 116, 4, '2024-03-01', NULL,         'active');

-- Customer 117: Pro since Apr, cancels May, reactivates Jul on Business
INSERT INTO subscriptions VALUES (19, 117, 3, '2024-04-10', '2024-05-20', 'canceled');
INSERT INTO subscriptions VALUES (20, 117, 4, '2024-07-01', NULL,         'active');

-- Customer 118: Growth since Jun
INSERT INTO subscriptions VALUES (21, 118, 2, '2024-06-01', NULL,         'active');

-- Customer 119: Starter since Jan, stable
INSERT INTO subscriptions VALUES (22, 119, 1, '2024-01-25', NULL,         'active');

-- Customer 120: Business since May, downgrades to Growth in Aug
INSERT INTO subscriptions VALUES (23, 120, 2, '2024-05-10', NULL,         'active');

-- Customer 121: Pro since Feb, cancels Apr
INSERT INTO subscriptions VALUES (24, 121, 3, '2024-02-15', '2024-04-01', 'canceled');

-- Customer 122: Growth since Jun, upgrades to Pro Jul
INSERT INTO subscriptions VALUES (25, 122, 3, '2024-06-15', NULL,         'active');

-- Customer 123: Enterprise since Jan, cancels Aug
INSERT INTO subscriptions VALUES (26, 123, 5, '2024-01-01', '2024-08-01', 'canceled');

-- Customer 124: Starter since Mar, upgrades to Growth Apr, to Pro Jun, to Business Aug
INSERT INTO subscriptions VALUES (27, 124, 4, '2024-03-05', NULL,         'active');

-- Customer 125: Growth since Jul
INSERT INTO subscriptions VALUES (28, 125, 2, '2024-07-01', NULL,         'active');

-- Customer 126: Pro since May, cancels Jun, reactivates Aug on Enterprise
INSERT INTO subscriptions VALUES (29, 126, 3, '2024-05-05', '2024-06-10', 'canceled');
INSERT INTO subscriptions VALUES (30, 126, 5, '2024-08-01', NULL,         'active');

-- Customer 127: Starter since Apr, cancels May (single-month customer)
INSERT INTO subscriptions VALUES (31, 127, 1, '2024-04-01', '2024-05-01', 'canceled');

-- Customer 128: Business since Feb, upgrades to Enterprise Mar
INSERT INTO subscriptions VALUES (32, 128, 5, '2024-02-05', NULL,         'active');

-- Customer 129: Growth since Jul, downgrades to Starter Aug
INSERT INTO subscriptions VALUES (33, 129, 1, '2024-07-10', NULL,         'active');

-- Customer 130: Pro since Aug (brand new, latest month)
INSERT INTO subscriptions VALUES (34, 130, 3, '2024-08-01', NULL,         'active');

-- Customer 131: Starter since Jun, cancels Jul, reactivates same month Jul on Growth
INSERT INTO subscriptions VALUES (35, 131, 1, '2024-06-05', '2024-07-01', 'canceled');
INSERT INTO subscriptions VALUES (36, 131, 2, '2024-07-15', NULL,         'active');

-- ----------------------------------------
-- Billing Events (64 rows)
-- Tracks every MRR movement for waterfall computation
-- ----------------------------------------

-- === JANUARY 2024 — Initial customers ===
-- New subscriptions
INSERT INTO billing_events VALUES (1,  1,  101, 'new',          NULL, 1,  0.00,   29.00, '2024-01-10');
INSERT INTO billing_events VALUES (2,  2,  102, 'new',          NULL, 2,  0.00,   79.00, '2024-01-15');
INSERT INTO billing_events VALUES (3,  3,  103, 'new',          NULL, 3,  0.00,  149.00, '2024-01-05');
INSERT INTO billing_events VALUES (4,  6,  105, 'new',          NULL, 4,  0.00,  299.00, '2024-01-20');
INSERT INTO billing_events VALUES (5,  9,  108, 'new',          NULL, 1,  0.00,   29.00, '2024-01-12');
INSERT INTO billing_events VALUES (6,  12, 111, 'new',          NULL, 1,  0.00,   29.00, '2024-01-08');
INSERT INTO billing_events VALUES (7,  15, 113, 'new',          NULL, 4,  0.00,  299.00, '2024-01-18');
INSERT INTO billing_events VALUES (8,  22, 119, 'new',          NULL, 1,  0.00,   29.00, '2024-01-25');
INSERT INTO billing_events VALUES (9,  26, 123, 'new',          NULL, 5,  0.00,  599.00, '2024-01-01');

-- === FEBRUARY 2024 ===
-- New subscriptions
INSERT INTO billing_events VALUES (10, 4,  104, 'new',          NULL, 1,  0.00,   29.00, '2024-02-01');
INSERT INTO billing_events VALUES (11, 7,  106, 'new',          NULL, 2,  0.00,   79.00, '2024-02-10');
INSERT INTO billing_events VALUES (12, 10, 109, 'new',          NULL, 5,  0.00,  599.00, '2024-02-01');
INSERT INTO billing_events VALUES (13, 17, 115, 'new',          NULL, 1,  0.00,   29.00, '2024-02-20');
INSERT INTO billing_events VALUES (14, 24, 121, 'new',          NULL, 3,  0.00,  149.00, '2024-02-15');
INSERT INTO billing_events VALUES (15, 32, 128, 'new',          NULL, 4,  0.00,  299.00, '2024-02-05');
-- Upgrades
INSERT INTO billing_events VALUES (16, 9,  108, 'upgrade',      1,   2,  29.00,  79.00, '2024-02-12');
-- Cancellations (churn)
INSERT INTO billing_events VALUES (17, 12, 111, 'cancellation', 1, NULL, 29.00,   0.00, '2024-02-10');

-- === MARCH 2024 ===
-- New subscriptions
INSERT INTO billing_events VALUES (18, 8,  107, 'new',          NULL, 3,  0.00,  149.00, '2024-03-01');
INSERT INTO billing_events VALUES (19, 11, 110, 'new',          NULL, 2,  0.00,   79.00, '2024-03-15');
INSERT INTO billing_events VALUES (20, 18, 116, 'new',          NULL, 5,  0.00,  599.00, '2024-03-01');
INSERT INTO billing_events VALUES (21, 27, 124, 'new',          NULL, 1,  0.00,   29.00, '2024-03-05');
-- Upgrades
INSERT INTO billing_events VALUES (22, 1,  101, 'upgrade',      1,   2,  29.00,  79.00, '2024-03-10');
INSERT INTO billing_events VALUES (23, 32, 128, 'upgrade',      4,   5, 299.00, 599.00, '2024-03-08');
-- Downgrades
INSERT INTO billing_events VALUES (24, 15, 113, 'downgrade',    4,   3, 299.00, 149.00, '2024-03-20');
-- Cancellations (churn)
INSERT INTO billing_events VALUES (25, 7,  106, 'cancellation', 2, NULL, 79.00,   0.00, '2024-03-15');

-- === APRIL 2024 ===
-- New subscriptions
INSERT INTO billing_events VALUES (26, 14, 112, 'new',          NULL, 3,  0.00,  149.00, '2024-04-05');
INSERT INTO billing_events VALUES (27, 19, 117, 'new',          NULL, 3,  0.00,  149.00, '2024-04-10');
INSERT INTO billing_events VALUES (28, 31, 127, 'new',          NULL, 1,  0.00,   29.00, '2024-04-01');
-- Upgrades
INSERT INTO billing_events VALUES (29, 27, 124, 'upgrade',      1,   2,  29.00,  79.00, '2024-04-10');
-- Downgrades
INSERT INTO billing_events VALUES (30, 2,  102, 'downgrade',    2,   1,  79.00,  29.00, '2024-04-05');
-- Reactivations
INSERT INTO billing_events VALUES (31, 13, 111, 'reactivation', NULL, 1,  0.00,   29.00, '2024-04-01');
-- Cancellations
INSERT INTO billing_events VALUES (32, 4,  104, 'cancellation', 1, NULL, 29.00,   0.00, '2024-04-15');
INSERT INTO billing_events VALUES (33, 24, 121, 'cancellation', 3, NULL,149.00,   0.00, '2024-04-01');

-- === MAY 2024 ===
-- New subscriptions
INSERT INTO billing_events VALUES (34, 16, 114, 'new',          NULL, 2,  0.00,   79.00, '2024-05-01');
INSERT INTO billing_events VALUES (35, 23, 120, 'new',          NULL, 4,  0.00,  299.00, '2024-05-10');
INSERT INTO billing_events VALUES (36, 29, 126, 'new',          NULL, 3,  0.00,  149.00, '2024-05-05');
-- Upgrades
INSERT INTO billing_events VALUES (37, 9,  108, 'upgrade',      2,   3,  79.00, 149.00, '2024-05-15');
INSERT INTO billing_events VALUES (38, 6,  105, 'upgrade',      4,   5, 299.00, 599.00, '2024-05-01');
-- Upgrades (customer 111: Starter -> Growth)
INSERT INTO billing_events VALUES (39, 13, 111, 'upgrade',      1,   2,  29.00,  79.00, '2024-05-10');
-- Cancellations
INSERT INTO billing_events VALUES (40, 19, 117, 'cancellation', 3, NULL,149.00,   0.00, '2024-05-20');
INSERT INTO billing_events VALUES (41, 31, 127, 'cancellation', 1, NULL, 29.00,   0.00, '2024-05-01');

-- === JUNE 2024 ===
-- New subscriptions
INSERT INTO billing_events VALUES (42, 21, 118, 'new',          NULL, 2,  0.00,   79.00, '2024-06-01');
INSERT INTO billing_events VALUES (43, 25, 122, 'new',          NULL, 2,  0.00,   79.00, '2024-06-15');
INSERT INTO billing_events VALUES (44, 35, 131, 'new',          NULL, 1,  0.00,   29.00, '2024-06-05');
-- Upgrades
INSERT INTO billing_events VALUES (45, 27, 124, 'upgrade',      2,   3,  79.00, 149.00, '2024-06-01');
INSERT INTO billing_events VALUES (46, 17, 115, 'upgrade',      1,   4,  29.00, 299.00, '2024-06-15');
-- Reactivations
INSERT INTO billing_events VALUES (47, 5,  104, 'reactivation', NULL, 2,  0.00,   79.00, '2024-06-01');
-- Cancellations
INSERT INTO billing_events VALUES (48, 2,  102, 'cancellation', 1, NULL, 29.00,   0.00, '2024-06-01');
INSERT INTO billing_events VALUES (49, 29, 126, 'cancellation', 3, NULL,149.00,   0.00, '2024-06-10');

-- === JULY 2024 ===
-- New subscriptions
INSERT INTO billing_events VALUES (50, 28, 125, 'new',          NULL, 2,  0.00,   79.00, '2024-07-01');
-- Upgrades
INSERT INTO billing_events VALUES (51, 25, 122, 'upgrade',      2,   3,  79.00, 149.00, '2024-07-05');
-- Downgrades
INSERT INTO billing_events VALUES (52, 8,  107, 'downgrade',    3,   2, 149.00,  79.00, '2024-07-01');  -- was downgrade event_date in Jun brief, using Jul
INSERT INTO billing_events VALUES (53, 18, 116, 'downgrade',    5,   4, 599.00, 299.00, '2024-07-10');
-- Reactivations
INSERT INTO billing_events VALUES (54, 20, 117, 'reactivation', NULL, 4,  0.00,  299.00, '2024-07-01');
INSERT INTO billing_events VALUES (55, 36, 131, 'reactivation', NULL, 2,  0.00,   79.00, '2024-07-15');  -- same-month cancel+reactivate
-- Cancellations
INSERT INTO billing_events VALUES (56, 11, 110, 'cancellation', 2, NULL, 79.00,   0.00, '2024-07-01');
INSERT INTO billing_events VALUES (57, 15, 113, 'cancellation', 3, NULL,149.00,   0.00, '2024-07-15');
INSERT INTO billing_events VALUES (58, 35, 131, 'cancellation', 1, NULL, 29.00,   0.00, '2024-07-01');  -- churn before reactivation same month

-- === AUGUST 2024 ===
-- New subscriptions
INSERT INTO billing_events VALUES (59, 34, 130, 'new',          NULL, 3,  0.00,  149.00, '2024-08-01');
-- Upgrades
INSERT INTO billing_events VALUES (60, 27, 124, 'upgrade',      3,   4, 149.00, 299.00, '2024-08-05');
-- Downgrades
INSERT INTO billing_events VALUES (61, 23, 120, 'downgrade',    4,   2, 299.00,  79.00, '2024-08-10');
INSERT INTO billing_events VALUES (62, 33, 129, 'downgrade',    2,   1,  79.00,  29.00, '2024-08-15');
-- Reactivations
INSERT INTO billing_events VALUES (63, 30, 126, 'reactivation', NULL, 5,  0.00,  599.00, '2024-08-01');
-- Cancellations
INSERT INTO billing_events VALUES (64, 26, 123, 'cancellation', 5, NULL,599.00,   0.00, '2024-08-01');
