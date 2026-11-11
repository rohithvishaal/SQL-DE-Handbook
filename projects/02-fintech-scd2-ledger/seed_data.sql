-- ============================================================================
-- Project 2: FinTech SCD2 Ledger — Seed Data
-- ============================================================================
-- Realistic mock data for testing SCD2 balance tracking, out-of-order
-- transaction handling, and reconciliation.
--
-- KEY EDGE CASES SEEDED:
--   1. Out-of-order transactions (posted_date >> transaction_date)
--   2. Same-second transactions on one account (tie-breaking needed)
--   3. Multiple source systems with varying latency
--   4. Account with zero balance after debits
--   5. Frozen account with transactions
--   6. High-volume account with many transactions
-- ============================================================================

-- ============================================================================
-- ACCOUNTS (10 accounts)
-- ============================================================================
INSERT INTO accounts (account_id, account_number, account_holder, account_type, current_balance, currency, status, opened_at, updated_at) VALUES
(1,  'ACC-10001', 'Alice Johnson',      'checking',    5250.00,  'USD', 'active',  '2024-01-02 09:00:00', '2024-01-20 14:30:00'),
(2,  'ACC-10002', 'Bob Martinez',        'savings',     13800.50, 'USD', 'active',  '2024-01-03 10:15:00', '2024-01-19 11:00:00'),
(3,  'ACC-10003', 'Carol Chen',          'checking',    340.75,   'USD', 'active',  '2024-01-05 08:30:00', '2024-01-21 09:45:00'),
(4,  'ACC-10004', 'David Okafor',        'investment',  45000.00, 'USD', 'active',  '2024-01-02 11:00:00', '2024-01-18 16:00:00'),
(5,  'ACC-10005', 'Elena Petrov',        'checking',    0.00,     'USD', 'active',  '2024-01-04 14:00:00', '2024-01-20 08:00:00'),
(6,  'ACC-10006', 'Frank Williams',      'savings',     8750.25,  'USD', 'frozen',  '2024-01-03 09:30:00', '2024-01-17 12:00:00'),
(7,  'ACC-10007', 'Grace Kim',           'checking',    2100.00,  'USD', 'active',  '2024-01-06 10:00:00', '2024-01-21 10:30:00'),
(8,  'ACC-10008', 'Hector Ramirez',      'investment',  67500.00, 'USD', 'active',  '2024-01-02 08:00:00', '2024-01-20 15:00:00'),
(9,  'ACC-10009', 'Irene Nakamura',      'savings',     3200.00,  'USD', 'active',  '2024-01-05 11:30:00', '2024-01-19 14:00:00'),
(10, 'ACC-10010', 'James O''Brien',      'checking',    15400.00, 'USD', 'closed',  '2024-01-02 09:45:00', '2024-01-15 17:00:00');

-- ============================================================================
-- TRANSACTIONS (52 rows — includes out-of-order and edge cases)
-- ============================================================================
-- Legend for out-of-order rows: marked with *** in comments
-- Out-of-order = posted_date is significantly later than transaction_date

INSERT INTO transactions (transaction_id, account_id, transaction_type, amount, transaction_date, posted_date, description, reference_id, source_system, created_at) VALUES
-- === Account 1: Alice Johnson (checking) — 8 transactions ===
(101, 1, 'credit', 10000.00, '2024-01-02 09:00:00', '2024-01-02 09:00:00', 'Initial deposit',                  'REF-INIT-001',  'INTERNAL', '2024-01-02 09:00:00'),
(102, 1, 'debit',  2500.00,  '2024-01-05 10:30:00', '2024-01-05 10:35:00', 'Rent payment - Jan 2024',          'CHK-4501',      'ACH',      '2024-01-05 10:35:00'),
(103, 1, 'debit',  150.00,   '2024-01-08 14:20:00', '2024-01-08 14:20:00', 'Electric bill autopay',            'ACH-88201',     'ACH',      '2024-01-08 14:20:00'),
(104, 1, 'credit', 3500.00,  '2024-01-10 08:00:00', '2024-01-10 08:05:00', 'Payroll direct deposit',           'PAY-2024-01A',  'ACH',      '2024-01-10 08:05:00'),
(105, 1, 'debit',  75.00,    '2024-01-07 11:00:00', '2024-01-11 09:00:00', 'Gas station purchase',             'CARD-77012',    'CARD',     '2024-01-11 09:00:00'),  -- *** OUT-OF-ORDER: txn on Jan 7, posted Jan 11
(106, 1, 'debit',  200.00,   '2024-01-12 16:45:00', '2024-01-12 16:50:00', 'Online shopping',                  'CARD-77055',    'CARD',     '2024-01-12 16:50:00'),
(107, 1, 'credit', 500.00,   '2024-01-06 09:00:00', '2024-01-14 10:00:00', 'Refund - returned merchandise',    'REF-RET-3301',  'CARD',     '2024-01-14 10:00:00'),  -- *** OUT-OF-ORDER: txn on Jan 6, posted Jan 14
(108, 1, 'debit',  5825.00,  '2024-01-20 14:30:00', '2024-01-20 14:30:00', 'Wire transfer to savings',         'WIRE-90001',    'WIRE',     '2024-01-20 14:30:00'),

-- === Account 2: Bob Martinez (savings) — 7 transactions ===
(201, 2, 'credit', 10000.00, '2024-01-03 10:15:00', '2024-01-03 10:15:00', 'Initial deposit',                  'REF-INIT-002',  'INTERNAL', '2024-01-03 10:15:00'),
(202, 2, 'credit', 1500.00,  '2024-01-07 09:00:00', '2024-01-07 09:05:00', 'Transfer from checking',           'INT-XFR-001',   'INTERNAL', '2024-01-07 09:05:00'),
(203, 2, 'credit', 2000.00,  '2024-01-10 08:00:00', '2024-01-10 08:00:00', 'Payroll bonus deposit',            'PAY-2024-01B',  'ACH',      '2024-01-10 08:00:00'),
(204, 2, 'debit',  500.00,   '2024-01-09 14:00:00', '2024-01-12 09:00:00', 'ATM withdrawal',                   'ATM-55023',     'CARD',     '2024-01-12 09:00:00'),  -- *** OUT-OF-ORDER: txn on Jan 9, posted Jan 12
(205, 2, 'credit', 300.50,   '2024-01-14 10:30:00', '2024-01-14 10:30:00', 'Interest credit - January',        'INT-JAN-002',   'INTERNAL', '2024-01-14 10:30:00'),
(206, 2, 'debit',  200.00,   '2024-01-16 11:00:00', '2024-01-16 11:05:00', 'Subscription service',             'ACH-SUB-042',   'ACH',      '2024-01-16 11:05:00'),
(207, 2, 'credit', 700.00,   '2024-01-08 15:00:00', '2024-01-19 11:00:00', 'Late-posted check deposit',        'CHK-DEP-8820',  'ACH',      '2024-01-19 11:00:00'),  -- *** OUT-OF-ORDER: txn on Jan 8, posted Jan 19

-- === Account 3: Carol Chen (checking) — 7 transactions ===
(301, 3, 'credit', 2000.00,  '2024-01-05 08:30:00', '2024-01-05 08:30:00', 'Initial deposit',                  'REF-INIT-003',  'INTERNAL', '2024-01-05 08:30:00'),
(302, 3, 'debit',  850.00,   '2024-01-08 09:15:00', '2024-01-08 09:20:00', 'Insurance premium',                'ACH-INS-101',   'ACH',      '2024-01-08 09:20:00'),
(303, 3, 'debit',  45.50,    '2024-01-10 12:00:00', '2024-01-10 12:00:00', 'Streaming subscription',           'CARD-STR-009',  'CARD',     '2024-01-10 12:00:00'),
(304, 3, 'credit', 1200.00,  '2024-01-12 08:00:00', '2024-01-12 08:05:00', 'Freelance payment',                'WIRE-FRL-401',  'WIRE',     '2024-01-12 08:05:00'),
(305, 3, 'debit',  500.00,   '2024-01-11 16:00:00', '2024-01-15 08:00:00', 'Medical copay',                    'CARD-MED-220',  'CARD',     '2024-01-15 08:00:00'),  -- *** OUT-OF-ORDER: txn on Jan 11, posted Jan 15
(306, 3, 'debit',  1200.00,  '2024-01-18 10:00:00', '2024-01-18 10:05:00', 'Rent payment',                     'ACH-RENT-003',  'ACH',      '2024-01-18 10:05:00'),
(307, 3, 'debit',  263.75,   '2024-01-21 09:45:00', '2024-01-21 09:45:00', 'Grocery shopping',                 'CARD-GRO-890',  'CARD',     '2024-01-21 09:45:00'),

-- === Account 4: David Okafor (investment) — 5 transactions ===
(401, 4, 'credit', 50000.00, '2024-01-02 11:00:00', '2024-01-02 11:00:00', 'Initial investment deposit',       'REF-INIT-004',  'WIRE',     '2024-01-02 11:00:00'),
(402, 4, 'debit',  10000.00, '2024-01-08 09:30:00', '2024-01-08 09:30:00', 'Stock purchase - AAPL',            'TRD-AAPL-001',  'INTERNAL', '2024-01-08 09:30:00'),
(403, 4, 'credit', 350.00,   '2024-01-12 16:00:00', '2024-01-12 16:00:00', 'Dividend - MSFT',                  'DIV-MSFT-Q4',   'INTERNAL', '2024-01-12 16:00:00'),
(404, 4, 'debit',  5000.00,  '2024-01-06 10:00:00', '2024-01-15 09:00:00', 'Bond purchase - settled late',     'TRD-BND-005',   'WIRE',     '2024-01-15 09:00:00'),  -- *** OUT-OF-ORDER: txn on Jan 6, posted Jan 15
(405, 4, 'credit', 9650.00,  '2024-01-18 14:00:00', '2024-01-18 16:00:00', 'Stock sale - AAPL',                'TRD-AAPL-002',  'INTERNAL', '2024-01-18 16:00:00'),

-- === Account 5: Elena Petrov (checking) — drained to zero — 5 transactions ===
(501, 5, 'credit', 3000.00,  '2024-01-04 14:00:00', '2024-01-04 14:00:00', 'Initial deposit',                  'REF-INIT-005',  'INTERNAL', '2024-01-04 14:00:00'),
(502, 5, 'debit',  1500.00,  '2024-01-09 10:00:00', '2024-01-09 10:05:00', 'Tuition payment',                  'ACH-EDU-301',   'ACH',      '2024-01-09 10:05:00'),
(503, 5, 'debit',  800.00,   '2024-01-12 14:30:00', '2024-01-12 14:30:00', 'Car payment',                      'ACH-AUTO-055',  'ACH',      '2024-01-12 14:30:00'),
(504, 5, 'credit', 500.00,   '2024-01-15 08:00:00', '2024-01-15 08:00:00', 'Venmo transfer received',          'INT-VEN-882',   'INTERNAL', '2024-01-15 08:00:00'),
(505, 5, 'debit',  1200.00,  '2024-01-20 08:00:00', '2024-01-20 08:00:00', 'Rent payment - zeroes balance',    'ACH-RENT-005',  'ACH',      '2024-01-20 08:00:00'),

-- === Account 6: Frank Williams (savings, FROZEN) — 4 transactions ===
(601, 6, 'credit', 8000.00,  '2024-01-03 09:30:00', '2024-01-03 09:30:00', 'Initial deposit',                  'REF-INIT-006',  'WIRE',     '2024-01-03 09:30:00'),
(602, 6, 'credit', 1000.00,  '2024-01-07 11:00:00', '2024-01-07 11:00:00', 'Transfer from checking',           'INT-XFR-006',   'INTERNAL', '2024-01-07 11:00:00'),
(603, 6, 'debit',  250.00,   '2024-01-10 15:00:00', '2024-01-10 15:05:00', 'Recurring bill',                   'ACH-BILL-066',  'ACH',      '2024-01-10 15:05:00'),
(604, 6, 'credit', 0.25,     '2024-01-17 12:00:00', '2024-01-17 12:00:00', 'Interest credit - January',        'INT-JAN-006',   'INTERNAL', '2024-01-17 12:00:00'),

-- === Account 7: Grace Kim (checking) — 5 transactions ===
(701, 7, 'credit', 3000.00,  '2024-01-06 10:00:00', '2024-01-06 10:00:00', 'Initial deposit',                  'REF-INIT-007',  'INTERNAL', '2024-01-06 10:00:00'),
(702, 7, 'debit',  400.00,   '2024-01-09 13:30:00', '2024-01-09 13:30:00', 'Utility bill',                     'ACH-UTIL-707',  'ACH',      '2024-01-09 13:30:00'),
(703, 7, 'debit',  250.00,   '2024-01-09 13:30:00', '2024-01-09 13:30:00', 'Internet bill',                    'ACH-UTIL-708',  'ACH',      '2024-01-09 13:30:00'),  -- SAME TIMESTAMP as 702 (tie-breaking test)
(704, 7, 'credit', 1500.00,  '2024-01-14 08:00:00', '2024-01-14 08:05:00', 'Payroll deposit',                  'PAY-2024-01G',  'ACH',      '2024-01-14 08:05:00'),
(705, 7, 'debit',  1750.00,  '2024-01-21 10:30:00', '2024-01-21 10:30:00', 'Rent payment',                     'ACH-RENT-007',  'ACH',      '2024-01-21 10:30:00'),

-- === Account 8: Hector Ramirez (investment) — 5 transactions ===
(801, 8, 'credit', 75000.00, '2024-01-02 08:00:00', '2024-01-02 08:00:00', 'Initial investment deposit',       'REF-INIT-008',  'WIRE',     '2024-01-02 08:00:00'),
(802, 8, 'debit',  15000.00, '2024-01-05 10:00:00', '2024-01-05 10:00:00', 'ETF purchase - SPY',               'TRD-SPY-001',   'INTERNAL', '2024-01-05 10:00:00'),
(803, 8, 'credit', 2500.00,  '2024-01-11 09:00:00', '2024-01-11 09:00:00', 'Dividend - index fund',            'DIV-IDX-Q4',    'INTERNAL', '2024-01-11 09:00:00'),
(804, 8, 'debit',  3000.00,  '2024-01-04 14:00:00', '2024-01-16 09:00:00', 'Bond purchase - T-bill settled',   'TRD-TBILL-002', 'WIRE',     '2024-01-16 09:00:00'),  -- *** OUT-OF-ORDER: txn on Jan 4, posted Jan 16
(805, 8, 'credit', 8000.00,  '2024-01-20 15:00:00', '2024-01-20 15:00:00', 'Stock sale - TSLA',                'TRD-TSLA-003',  'INTERNAL', '2024-01-20 15:00:00'),

-- === Account 9: Irene Nakamura (savings) — 4 transactions ===
(901, 9, 'credit', 5000.00,  '2024-01-05 11:30:00', '2024-01-05 11:30:00', 'Initial deposit',                  'REF-INIT-009',  'INTERNAL', '2024-01-05 11:30:00'),
(902, 9, 'debit',  1000.00,  '2024-01-10 10:00:00', '2024-01-10 10:00:00', 'Transfer to checking',             'INT-XFR-009',   'INTERNAL', '2024-01-10 10:00:00'),
(903, 9, 'credit', 200.00,   '2024-01-15 09:00:00', '2024-01-15 09:00:00', 'Cash deposit at branch',           'BR-DEP-009',    'INTERNAL', '2024-01-15 09:00:00'),
(904, 9, 'debit',  1000.00,  '2024-01-19 14:00:00', '2024-01-19 14:00:00', 'Emergency fund withdrawal',        'ACH-EMR-009',   'ACH',      '2024-01-19 14:00:00'),

-- === Account 10: James O'Brien (checking, CLOSED) — 2 transactions ===
(1001, 10, 'credit', 20000.00, '2024-01-02 09:45:00', '2024-01-02 09:45:00', 'Initial deposit',                'REF-INIT-010',  'INTERNAL', '2024-01-02 09:45:00'),
(1002, 10, 'debit',   4600.00, '2024-01-15 17:00:00', '2024-01-15 17:00:00', 'Closing balance withdrawal',     'WIRE-CLS-010',  'WIRE',     '2024-01-15 17:00:00');

-- ============================================================================
-- ACCOUNT_HISTORY — SCD2 seed data (initial + in-order states only)
-- ============================================================================
-- This seeds the initial opening-balance records ($0.00 pre-deposit state
-- starting 1 second before opened_at so valid_to > valid_from holds) and
-- initial deposit states. Section 1 / Section 3 of solution.sql build out
-- the remaining history chain, including out-of-order retroactive inserts.
-- ============================================================================

INSERT INTO account_history (history_id, account_id, balance, transaction_id, valid_from, valid_to, is_current, created_at, modified_at) VALUES
-- Account 1: Alice — opening balance
(1,  1,  0.00,      NULL, '2024-01-02 08:59:59', '2024-01-02 09:00:00', FALSE, '2024-01-02 09:00:00', '2024-01-02 09:00:00'),
(2,  1,  10000.00,  101,  '2024-01-02 09:00:00', '9999-12-31 23:59:59', TRUE,  '2024-01-02 09:00:00', '2024-01-02 09:00:00'),

-- Account 2: Bob — opening balance
(3,  2,  0.00,      NULL, '2024-01-03 10:14:59', '2024-01-03 10:15:00', FALSE, '2024-01-03 10:15:00', '2024-01-03 10:15:00'),
(4,  2,  10000.00,  201,  '2024-01-03 10:15:00', '9999-12-31 23:59:59', TRUE,  '2024-01-03 10:15:00', '2024-01-03 10:15:00'),

-- Account 3: Carol — opening balance
(5,  3,  0.00,      NULL, '2024-01-05 08:29:59', '2024-01-05 08:30:00', FALSE, '2024-01-05 08:30:00', '2024-01-05 08:30:00'),
(6,  3,  2000.00,   301,  '2024-01-05 08:30:00', '9999-12-31 23:59:59', TRUE,  '2024-01-05 08:30:00', '2024-01-05 08:30:00'),

-- Account 4: David — opening balance
(7,  4,  0.00,      NULL, '2024-01-02 10:59:59', '2024-01-02 11:00:00', FALSE, '2024-01-02 11:00:00', '2024-01-02 11:00:00'),
(8,  4,  50000.00,  401,  '2024-01-02 11:00:00', '9999-12-31 23:59:59', TRUE,  '2024-01-02 11:00:00', '2024-01-02 11:00:00'),

-- Account 5: Elena — opening balance
(9,  5,  0.00,      NULL, '2024-01-04 13:59:59', '2024-01-04 14:00:00', FALSE, '2024-01-04 14:00:00', '2024-01-04 14:00:00'),
(10, 5,  3000.00,   501,  '2024-01-04 14:00:00', '9999-12-31 23:59:59', TRUE,  '2024-01-04 14:00:00', '2024-01-04 14:00:00'),

-- Account 6: Frank — opening balance
(11, 6,  0.00,      NULL, '2024-01-03 09:29:59', '2024-01-03 09:30:00', FALSE, '2024-01-03 09:30:00', '2024-01-03 09:30:00'),
(12, 6,  8000.00,   601,  '2024-01-03 09:30:00', '9999-12-31 23:59:59', TRUE,  '2024-01-03 09:30:00', '2024-01-03 09:30:00'),

-- Account 7: Grace — opening balance
(13, 7,  0.00,      NULL, '2024-01-06 09:59:59', '2024-01-06 10:00:00', FALSE, '2024-01-06 10:00:00', '2024-01-06 10:00:00'),
(14, 7,  3000.00,   701,  '2024-01-06 10:00:00', '9999-12-31 23:59:59', TRUE,  '2024-01-06 10:00:00', '2024-01-06 10:00:00'),

-- Account 8: Hector — opening balance
(15, 8,  0.00,      NULL, '2024-01-02 07:59:59', '2024-01-02 08:00:00', FALSE, '2024-01-02 08:00:00', '2024-01-02 08:00:00'),
(16, 8,  75000.00,  801,  '2024-01-02 08:00:00', '9999-12-31 23:59:59', TRUE,  '2024-01-02 08:00:00', '2024-01-02 08:00:00'),

-- Account 9: Irene — opening balance
(17, 9,  0.00,      NULL, '2024-01-05 11:29:59', '2024-01-05 11:30:00', FALSE, '2024-01-05 11:30:00', '2024-01-05 11:30:00'),
(18, 9,  5000.00,   901,  '2024-01-05 11:30:00', '9999-12-31 23:59:59', TRUE,  '2024-01-05 11:30:00', '2024-01-05 11:30:00'),

-- Account 10: James — opening balance & closed final state
(19, 10, 0.00,      NULL, '2024-01-02 09:44:59', '2024-01-02 09:45:00', FALSE, '2024-01-02 09:45:00', '2024-01-02 09:45:00'),
(20, 10, 20000.00,  1001, '2024-01-02 09:45:00', '2024-01-15 17:00:00', FALSE, '2024-01-02 09:45:00', '2024-01-15 17:00:00'),
(21, 10, 15400.00,  1002, '2024-01-15 17:00:00', '9999-12-31 23:59:59', TRUE,  '2024-01-15 17:00:00', '2024-01-15 17:00:00');
