-- ============================================================================
-- Project 2: FinTech SCD2 Ledger — Reference Solution
-- ============================================================================
-- This file implements:
--   1. MERGE-based SCD2 pipeline for processing transactions
--   2. Out-of-order (late-arriving) transaction handling
--   3. Reconciliation queries (balance verification)
--   4. Point-in-time balance lookup
--   5. Idempotency checks
--   6. Gap/overlap detection in history chains
--
-- All queries use ANSI SQL with CTEs for readability.
-- ============================================================================


-- ############################################################################
-- SECTION 1: MERGE-BASED SCD2 UPDATE
-- ############################################################################
-- Process a batch of new transactions into the account_history SCD2 table.
-- This uses the standard single-statement ANSI SQL MERGE pattern (supported in
-- PostgreSQL 15+, Snowflake, BigQuery, Databricks, DuckDB, Oracle, SQL Server).
--
-- STRATEGY (Two-Branch Staged MERGE):
--   Branch 1 ("CLOSE"):  Matched on (account_id, is_current = TRUE) → closes
--                        the currently open record by setting valid_to to the
--                        first new transaction's effective_ts & is_current = FALSE.
--   Branch 2 ("INSERT"): Forced unmatched (match_account_id IS NULL) → inserts
--                        one new history row per transaction with running balance.
--
-- SAME-SECOND TIE-BREAKING:
--   When multiple transactions on one account share an identical timestamp
--   (e.g., Account 7 txns 702 & 703 at '2024-01-09 13:30:00'), we offset
--   effective_ts by (same_ts_seq - 1) * INTERVAL '1' SECOND so every SCD2 row
--   strictly satisfies CHECK (valid_to > valid_from) with zero gaps/overlaps.
--   (Snowflake: DATEADD('second', offset, ts); BigQuery: TIMESTAMP_ADD)
-- ############################################################################

MERGE INTO account_history AS target
USING (
    WITH new_transaction_batch AS (
        -- Step 1a: Identify unprocessed transactions (idempotent via NOT EXISTS)
        SELECT
            t.transaction_id,
            t.account_id,
            t.transaction_type,
            t.amount,
            t.transaction_date,
            t.posted_date
        FROM transactions t
        WHERE t.posted_date > '2024-01-02 09:00:00'
          AND NOT EXISTS (
              SELECT 1
              FROM account_history ah
              WHERE ah.transaction_id = t.transaction_id
          )
    ),

    ordered_transactions AS (
        -- Step 1b: Order chronologically per account and assign same-second offset
        SELECT
            ntb.transaction_id,
            ntb.account_id,
            ntb.transaction_type,
            ntb.amount,
            ntb.transaction_date,
            ntb.posted_date,
            ROW_NUMBER() OVER (
                PARTITION BY ntb.account_id
                ORDER BY ntb.transaction_date ASC, ntb.transaction_id ASC
            ) AS txn_seq,
            ntb.transaction_date + (
                (ROW_NUMBER() OVER (
                    PARTITION BY ntb.account_id, ntb.transaction_date
                    ORDER BY ntb.transaction_id ASC
                ) - 1) * INTERVAL '1' SECOND
            ) AS effective_ts
        FROM new_transaction_batch ntb
    ),

    running_balances AS (
        -- Step 1c: Compute cumulative balance starting from current SCD2 balance
        SELECT
            ot.transaction_id,
            ot.account_id,
            ot.effective_ts,
            ot.txn_seq,
            ah_current.balance + SUM(
                CASE
                    WHEN ot.transaction_type = 'credit' THEN ot.amount
                    WHEN ot.transaction_type = 'debit'  THEN -1 * ot.amount
                END
            ) OVER (
                PARTITION BY ot.account_id
                ORDER BY ot.effective_ts ASC, ot.transaction_id ASC
                ROWS UNBOUNDED PRECEDING
            ) AS new_balance
        FROM ordered_transactions ot
        JOIN account_history ah_current
            ON  ah_current.account_id = ot.account_id
            AND ah_current.is_current = TRUE
    ),

    max_history AS (
        SELECT COALESCE(MAX(history_id), 0) AS max_id
        FROM account_history
    ),

    staged_scd2 AS (
        -- Branch 1: Close each affected account's existing is_current = TRUE row
        SELECT
            rb.account_id                       AS match_account_id,
            CAST(NULL AS INT)                   AS history_id,
            rb.account_id,
            CAST(NULL AS DECIMAL(15, 2))        AS balance,
            CAST(NULL AS INT)                   AS transaction_id,
            CAST(NULL AS TIMESTAMP)             AS valid_from,
            MIN(rb.effective_ts)                AS valid_to,
            FALSE                               AS is_current
        FROM running_balances rb
        GROUP BY rb.account_id

        UNION ALL

        -- Branch 2: Insert one new SCD2 row per incoming transaction
        SELECT
            CAST(NULL AS INT)                   AS match_account_id,
            mh.max_id + ROW_NUMBER() OVER (
                ORDER BY rb.account_id, rb.effective_ts, rb.transaction_id
            )                                   AS history_id,
            rb.account_id,
            rb.new_balance                      AS balance,
            rb.transaction_id,
            rb.effective_ts                     AS valid_from,
            COALESCE(
                LEAD(rb.effective_ts) OVER (
                    PARTITION BY rb.account_id
                    ORDER BY rb.effective_ts ASC, rb.transaction_id ASC
                ),
                '9999-12-31 23:59:59'
            )                                   AS valid_to,
            CASE
                WHEN LEAD(rb.transaction_id) OVER (
                    PARTITION BY rb.account_id
                    ORDER BY rb.effective_ts ASC, rb.transaction_id ASC
                ) IS NULL THEN TRUE
                ELSE FALSE
            END                                 AS is_current
        FROM running_balances rb
        CROSS JOIN max_history mh
    )

    SELECT * FROM staged_scd2
) AS src
ON  target.account_id = src.match_account_id
AND target.is_current = TRUE
WHEN MATCHED THEN
    UPDATE SET
        valid_to    = src.valid_to,
        is_current  = FALSE,
        modified_at = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (
        history_id, account_id, balance, transaction_id,
        valid_from, valid_to, is_current, created_at, modified_at
    )
    VALUES (
        src.history_id, src.account_id, src.balance, src.transaction_id,
        src.valid_from, src.valid_to, src.is_current, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    );


-- ############################################################################
-- SECTION 2: OUT-OF-ORDER (LATE-ARRIVING) TRANSACTION HANDLING
-- ############################################################################
-- When a transaction arrives with a transaction_date EARLIER than the
-- most recent history record's valid_from, we must:
--   1. Find where it belongs in the timeline
--   2. Insert a new history record at that point
--   3. Recalculate all subsequent balances in the chain
--   4. Adjust valid_from/valid_to of surrounding records
--
-- This is the hardest part of SCD2 maintenance.
-- ############################################################################

-- ---------------------------------------------------------------------------
-- Step 2a: Identify late-arriving transactions
-- ---------------------------------------------------------------------------
WITH late_transactions AS (
    SELECT
        t.transaction_id,
        t.account_id,
        t.transaction_type,
        t.amount,
        t.transaction_date,
        t.posted_date
    FROM transactions t
    WHERE t.posted_date > t.transaction_date + INTERVAL '1' DAY  -- arrived >1 day late
      AND NOT EXISTS (
          SELECT 1
          FROM account_history ah
          WHERE ah.transaction_id = t.transaction_id
      )
),

-- ---------------------------------------------------------------------------
-- Step 2b: Find the insertion point in the history chain
-- ---------------------------------------------------------------------------
-- For each late transaction, find the history record whose validity
-- window contains the transaction_date. This is where we need to split.
-- ---------------------------------------------------------------------------
insertion_points AS (
    SELECT
        lt.transaction_id,
        lt.account_id,
        lt.transaction_type,
        lt.amount,
        lt.transaction_date,
        ah.history_id    AS split_history_id,
        ah.balance       AS balance_before,
        ah.valid_from    AS original_valid_from,
        ah.valid_to      AS original_valid_to,
        ah.is_current    AS was_current
    FROM late_transactions lt
    JOIN account_history ah
        ON  ah.account_id = lt.account_id
        AND lt.transaction_date >= ah.valid_from
        AND lt.transaction_date <  ah.valid_to
),

-- ---------------------------------------------------------------------------
-- Step 2c: Compute the new balance after the late transaction
-- ---------------------------------------------------------------------------
new_states AS (
    SELECT
        ip.*,
        ip.balance_before + CASE
            WHEN ip.transaction_type = 'credit' THEN ip.amount
            WHEN ip.transaction_type = 'debit'  THEN -1 * ip.amount
        END AS new_balance,
        CASE
            WHEN ip.transaction_type = 'credit' THEN ip.amount
            WHEN ip.transaction_type = 'debit'  THEN -1 * ip.amount
        END AS balance_delta
    FROM insertion_points ip
)

-- Preview all late-arriving transactions and the history intervals they split
SELECT
    ns.transaction_id,
    ns.account_id,
    ns.transaction_date,
    ns.split_history_id,
    ns.balance_before,
    ns.balance_delta,
    ns.new_balance,
    ns.original_valid_from,
    ns.original_valid_to
FROM new_states ns
ORDER BY ns.account_id, ns.transaction_date, ns.transaction_id;

-- ---------------------------------------------------------------------------
-- Step 2d: Apply the retroactive changes
-- ---------------------------------------------------------------------------
-- Three operations per late transaction:
--
--   (i)   SHRINK the existing record: set valid_to = transaction_date
--   (ii)  INSERT the new record: valid_from = transaction_date,
--         valid_to = original valid_to of the shrunk record
--   (iii) ADJUST all subsequent records for this account: add the
--         balance_delta to their balance (the late txn's impact ripples)
-- ---------------------------------------------------------------------------

-- (i) Shrink the split record
-- UPDATE account_history
-- SET    valid_to    = ns.transaction_date,
--        is_current  = FALSE,
--        modified_at = CURRENT_TIMESTAMP
-- FROM   new_states ns
-- WHERE  account_history.history_id = ns.split_history_id;

-- (ii) Insert the new retroactive record
-- INSERT INTO account_history (...)
-- SELECT
--     next_id, ns.account_id, ns.new_balance, ns.transaction_id,
--     ns.transaction_date,        -- valid_from
--     ns.original_valid_to,       -- valid_to (inherits the original end)
--     ns.was_current,             -- is_current (TRUE if we split the current record)
--     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
-- FROM new_states ns;

-- (iii) Ripple: adjust all subsequent history records' balances
-- UPDATE account_history
-- SET    balance     = balance + ns.balance_delta,
--        modified_at = CURRENT_TIMESTAMP
-- FROM   new_states ns
-- WHERE  account_history.account_id = ns.account_id
--   AND  account_history.valid_from > ns.transaction_date;

-- ---------------------------------------------------------------------------
-- COMPLETE EXECUTABLE EXAMPLE: Process one late transaction end-to-end
-- ---------------------------------------------------------------------------
-- Scenario: Transaction 105 (Alice, $75 debit on Jan 7) posted on Jan 11
-- It should be inserted between the Jan 5 and Jan 8 history records.
-- ---------------------------------------------------------------------------

-- Step A: Find where Jan 7 falls in Alice's history
SELECT
    ah.history_id,
    ah.balance,
    ah.valid_from,
    ah.valid_to,
    ah.is_current,
    'This record spans Jan 7; we will split it here' AS action
FROM account_history ah
WHERE ah.account_id = 1
  AND '2024-01-07 11:00:00' >= ah.valid_from
  AND '2024-01-07 11:00:00' <  ah.valid_to;

-- Step B: Shrink the existing record to end at the late txn's date
-- (Run as UPDATE in production)
-- UPDATE account_history
-- SET valid_to = '2024-01-07 11:00:00', is_current = FALSE, modified_at = NOW()
-- WHERE history_id = <from step A>;

-- Step C: Insert the new record
-- INSERT INTO account_history (...)
-- VALUES (<next_id>, 1, <balance - 75.00>, 105,
--         '2024-01-07 11:00:00', <original_valid_to>, FALSE, NOW(), NOW());

-- Step D: Ripple the -75.00 delta to all subsequent records
-- UPDATE account_history SET balance = balance - 75.00
-- WHERE account_id = 1 AND valid_from > '2024-01-07 11:00:00';


-- ############################################################################
-- SECTION 3: FULL HISTORY REBUILD (ALTERNATIVE TO INCREMENTAL)
-- ############################################################################
-- For small-to-medium datasets, it can be simpler and safer to rebuild
-- the entire account_history from scratch using the transactions table.
-- This approach is naturally idempotent.
-- ############################################################################

-- ---------------------------------------------------------------------------
-- Rebuild complete SCD2 history from transactions
-- ---------------------------------------------------------------------------
WITH all_transactions_ordered AS (
    -- Order every transaction chronologically per account, with transaction_id
    -- as deterministic tiebreaker. Offset same-second ties (e.g., Account 7
    -- txns 702 & 703) by (same_ts_seq - 1) * INTERVAL '1' SECOND so every
    -- resulting SCD2 window strictly satisfies CHECK (valid_to > valid_from).
    SELECT
        t.transaction_id,
        t.account_id,
        t.transaction_type,
        t.amount,
        t.transaction_date,
        t.transaction_date + (
            (ROW_NUMBER() OVER (
                PARTITION BY t.account_id, t.transaction_date
                ORDER BY t.transaction_id ASC
            ) - 1) * INTERVAL '1' SECOND
        ) AS effective_ts,
        ROW_NUMBER() OVER (
            PARTITION BY t.account_id
            ORDER BY t.transaction_date ASC, t.transaction_id ASC
        ) AS seq
    FROM transactions t
),

-- ---------------------------------------------------------------------------
-- Compute running balance for each transaction
-- ---------------------------------------------------------------------------
cumulative_balances AS (
    SELECT
        ato.transaction_id,
        ato.account_id,
        ato.transaction_date,
        ato.effective_ts,
        ato.seq,
        SUM(
            CASE
                WHEN ato.transaction_type = 'credit' THEN ato.amount
                WHEN ato.transaction_type = 'debit'  THEN -1 * ato.amount
            END
        ) OVER (
            PARTITION BY ato.account_id
            ORDER BY ato.effective_ts ASC, ato.transaction_id ASC
            ROWS UNBOUNDED PRECEDING
        ) AS balance_after
    FROM all_transactions_ordered ato
),

-- ---------------------------------------------------------------------------
-- Build the SCD2 records with valid_from / valid_to windows
-- ---------------------------------------------------------------------------
scd2_records AS (
    SELECT
        cb.transaction_id,
        cb.account_id,
        cb.balance_after                                    AS balance,
        cb.effective_ts                                     AS valid_from,
        COALESCE(
            LEAD(cb.effective_ts) OVER (
                PARTITION BY cb.account_id
                ORDER BY cb.effective_ts ASC, cb.transaction_id ASC
            ),
            '9999-12-31 23:59:59'
        )                                                   AS valid_to,
        CASE
            WHEN LEAD(cb.transaction_id) OVER (
                PARTITION BY cb.account_id
                ORDER BY cb.effective_ts ASC, cb.transaction_id ASC
            ) IS NULL THEN TRUE
            ELSE FALSE
        END                                                 AS is_current
    FROM cumulative_balances cb
)

-- Preview the rebuilt history (in production: TRUNCATE + INSERT, or MERGE)
SELECT
    ROW_NUMBER() OVER (ORDER BY account_id, valid_from, transaction_id) AS history_id,
    account_id,
    balance,
    transaction_id,
    valid_from,
    valid_to,
    is_current
FROM scd2_records
ORDER BY account_id, valid_from, transaction_id;


-- ############################################################################
-- SECTION 4: RECONCILIATION QUERIES
-- ############################################################################
-- Verify data integrity by cross-checking balances from multiple sources.
-- ############################################################################

-- ---------------------------------------------------------------------------
-- 4a: Compare current_balance in accounts vs. sum of all transactions
-- ---------------------------------------------------------------------------
-- If these don't match, there's a data integrity issue.
-- ---------------------------------------------------------------------------
WITH transaction_sums AS (
    SELECT
        t.account_id,
        SUM(
            CASE
                WHEN t.transaction_type = 'credit' THEN t.amount
                WHEN t.transaction_type = 'debit'  THEN -1 * t.amount
            END
        ) AS computed_balance
    FROM transactions t
    GROUP BY t.account_id
)
SELECT
    a.account_id,
    a.account_number,
    a.account_holder,
    a.current_balance                         AS stored_balance,
    ts.computed_balance                        AS computed_from_transactions,
    a.current_balance - ts.computed_balance    AS discrepancy,
    CASE
        WHEN a.current_balance = ts.computed_balance THEN 'OK'
        ELSE '*** MISMATCH ***'
    END                                        AS status
FROM accounts a
JOIN transaction_sums ts ON a.account_id = ts.account_id
ORDER BY ABS(a.current_balance - ts.computed_balance) DESC;


-- ---------------------------------------------------------------------------
-- 4b: Compare current SCD2 balance vs. accounts.current_balance
-- ---------------------------------------------------------------------------
-- The is_current = TRUE record's balance should match accounts.current_balance
-- ---------------------------------------------------------------------------
SELECT
    a.account_id,
    a.account_number,
    a.current_balance                         AS balance_in_accounts,
    ah.balance                                AS balance_in_history,
    a.current_balance - ah.balance            AS discrepancy,
    CASE
        WHEN a.current_balance = ah.balance THEN 'OK'
        ELSE '*** MISMATCH ***'
    END                                        AS status
FROM accounts a
JOIN account_history ah
    ON  ah.account_id = a.account_id
    AND ah.is_current = TRUE
ORDER BY ABS(a.current_balance - ah.balance) DESC;


-- ---------------------------------------------------------------------------
-- 4c: Three-way reconciliation
-- ---------------------------------------------------------------------------
-- Cross-check all three sources: accounts table, SCD2 current, and
-- transaction sum. Any mismatch indicates a pipeline bug.
-- ---------------------------------------------------------------------------
WITH txn_totals AS (
    SELECT
        account_id,
        SUM(CASE WHEN transaction_type = 'credit' THEN amount ELSE -amount END) AS txn_balance
    FROM transactions
    GROUP BY account_id
),
scd2_current AS (
    SELECT account_id, balance AS scd2_balance
    FROM account_history
    WHERE is_current = TRUE
)
SELECT
    a.account_id,
    a.account_holder,
    a.current_balance    AS acct_balance,
    tt.txn_balance,
    sc.scd2_balance,
    CASE
        WHEN a.current_balance = tt.txn_balance
         AND a.current_balance = sc.scd2_balance
        THEN 'ALL MATCH'
        ELSE '*** DISCREPANCY ***'
    END AS reconciliation_status
FROM accounts a
LEFT JOIN txn_totals tt   ON a.account_id = tt.account_id
LEFT JOIN scd2_current sc ON a.account_id = sc.account_id
ORDER BY a.account_id;


-- ############################################################################
-- SECTION 5: POINT-IN-TIME BALANCE LOOKUP
-- ############################################################################
-- "What was account X's balance at time T?"
-- This is the primary reason for maintaining SCD2.
-- ############################################################################

-- ---------------------------------------------------------------------------
-- 5a: Single account, single point in time
-- ---------------------------------------------------------------------------
-- Example: What was Alice's balance on January 9, 2024 at noon?
-- ---------------------------------------------------------------------------
SELECT
    ah.account_id,
    a.account_holder,
    ah.balance,
    ah.valid_from,
    ah.valid_to,
    ah.transaction_id,
    '2024-01-09 12:00:00' AS query_timestamp
FROM account_history ah
JOIN accounts a ON a.account_id = ah.account_id
WHERE ah.account_id = 1
  AND '2024-01-09 12:00:00' >= ah.valid_from
  AND '2024-01-09 12:00:00' <  ah.valid_to;


-- ---------------------------------------------------------------------------
-- 5b: All accounts at a specific point in time (snapshot)
-- ---------------------------------------------------------------------------
-- Example: Portfolio snapshot as of January 15, 2024 at end of day
-- ---------------------------------------------------------------------------
SELECT
    ah.account_id,
    a.account_holder,
    a.account_type,
    ah.balance          AS balance_at_snapshot,
    ah.valid_from,
    ah.valid_to
FROM account_history ah
JOIN accounts a ON a.account_id = ah.account_id
WHERE '2024-01-15 23:59:59' >= ah.valid_from
  AND '2024-01-15 23:59:59' <  ah.valid_to
ORDER BY ah.account_id;


-- ---------------------------------------------------------------------------
-- 5c: Balance history timeline for a single account
-- ---------------------------------------------------------------------------
-- Full audit trail for Alice's account
-- ---------------------------------------------------------------------------
SELECT
    ah.history_id,
    ah.balance,
    ah.transaction_id,
    t.description       AS transaction_description,
    t.transaction_type,
    t.amount            AS transaction_amount,
    ah.valid_from,
    ah.valid_to,
    ah.is_current,
    CASE
        WHEN ah.is_current = TRUE THEN 'ACTIVE'
        ELSE 'HISTORICAL'
    END AS record_status
FROM account_history ah
LEFT JOIN transactions t ON t.transaction_id = ah.transaction_id
WHERE ah.account_id = 1
ORDER BY ah.valid_from ASC, ah.history_id ASC;


-- ############################################################################
-- SECTION 6: IDEMPOTENCY CHECK
-- ############################################################################
-- Ensure reprocessing a batch does not create duplicate history records.
-- ############################################################################

-- ---------------------------------------------------------------------------
-- 6a: Detect duplicate transaction_ids in history
-- ---------------------------------------------------------------------------
SELECT
    transaction_id,
    COUNT(*) AS occurrence_count
FROM account_history
WHERE transaction_id IS NOT NULL
GROUP BY transaction_id
HAVING COUNT(*) > 1;


-- ---------------------------------------------------------------------------
-- 6b: Detect overlapping validity windows (data corruption indicator)
-- ---------------------------------------------------------------------------
-- Two history records for the same account should NEVER have overlapping
-- [valid_from, valid_to) windows. If they do, the SCD2 chain is broken.
-- ---------------------------------------------------------------------------
SELECT
    a.history_id    AS record_a_id,
    b.history_id    AS record_b_id,
    a.account_id,
    a.valid_from    AS a_from,
    a.valid_to      AS a_to,
    b.valid_from    AS b_from,
    b.valid_to      AS b_to,
    'OVERLAP DETECTED' AS issue
FROM account_history a
JOIN account_history b
    ON  a.account_id = b.account_id
    AND a.history_id < b.history_id       -- avoid self-join and duplicates
    AND a.valid_from < b.valid_to         -- overlap condition
    AND b.valid_from < a.valid_to;


-- ---------------------------------------------------------------------------
-- 6c: Detect gaps in the history chain
-- ---------------------------------------------------------------------------
-- Adjacent records should have no gap: record N's valid_to should equal
-- record (N+1)'s valid_from.
-- ---------------------------------------------------------------------------
WITH ordered_history AS (
    SELECT
        history_id,
        account_id,
        valid_from,
        valid_to,
        LEAD(valid_from) OVER (
            PARTITION BY account_id
            ORDER BY valid_from, history_id
        ) AS next_valid_from
    FROM account_history
)
SELECT
    history_id,
    account_id,
    valid_to            AS current_record_ends,
    next_valid_from     AS next_record_starts,
    'GAP DETECTED'      AS issue
FROM ordered_history
WHERE next_valid_from IS NOT NULL     -- skip the last record
  AND valid_to <> next_valid_from;    -- gap exists


-- ############################################################################
-- SECTION 7: USEFUL ANALYTICAL QUERIES
-- ############################################################################

-- ---------------------------------------------------------------------------
-- 7a: Daily balance movements per account
-- ---------------------------------------------------------------------------
SELECT
    t.account_id,
    a.account_holder,
    CAST(t.transaction_date AS DATE) AS txn_date,
    SUM(CASE WHEN t.transaction_type = 'credit' THEN t.amount ELSE 0 END) AS total_credits,
    SUM(CASE WHEN t.transaction_type = 'debit'  THEN t.amount ELSE 0 END) AS total_debits,
    SUM(CASE WHEN t.transaction_type = 'credit' THEN t.amount ELSE -t.amount END) AS net_movement,
    COUNT(*) AS txn_count
FROM transactions t
JOIN accounts a ON a.account_id = t.account_id
GROUP BY t.account_id, a.account_holder, CAST(t.transaction_date AS DATE)
ORDER BY t.account_id, txn_date;


-- ---------------------------------------------------------------------------
-- 7b: Identify out-of-order transactions (late arrivals)
-- ---------------------------------------------------------------------------
-- Transactions where posting was delayed more than 24 hours
-- ---------------------------------------------------------------------------
SELECT
    t.transaction_id,
    t.account_id,
    a.account_holder,
    t.transaction_date,
    t.posted_date,
    t.posted_date - t.transaction_date        AS posting_delay,
    t.source_system,
    t.description,
    CASE
        WHEN t.posted_date - t.transaction_date > INTERVAL '3' DAY
            THEN 'CRITICAL - Investigate'
        WHEN t.posted_date - t.transaction_date > INTERVAL '1' DAY
            THEN 'WARNING - Late posting'
        ELSE 'Normal'
    END AS latency_severity
FROM transactions t
JOIN accounts a ON a.account_id = t.account_id
WHERE t.posted_date > t.transaction_date + INTERVAL '1' HOUR
ORDER BY (t.posted_date - t.transaction_date) DESC;


-- ---------------------------------------------------------------------------
-- 7c: Account balance volatility (standard deviation of daily movements)
-- ---------------------------------------------------------------------------
WITH daily_movements AS (
    SELECT
        t.account_id,
        CAST(t.transaction_date AS DATE) AS txn_date,
        SUM(CASE WHEN t.transaction_type = 'credit' THEN t.amount ELSE -t.amount END) AS net_daily
    FROM transactions t
    GROUP BY t.account_id, CAST(t.transaction_date AS DATE)
)
SELECT
    dm.account_id,
    a.account_holder,
    COUNT(*)                                AS active_days,
    ROUND(AVG(dm.net_daily), 2)             AS avg_daily_movement,
    ROUND(STDDEV(dm.net_daily), 2)          AS stddev_daily_movement,
    MIN(dm.net_daily)                       AS largest_daily_outflow,
    MAX(dm.net_daily)                       AS largest_daily_inflow
FROM daily_movements dm
JOIN accounts a ON a.account_id = dm.account_id
GROUP BY dm.account_id, a.account_holder
ORDER BY stddev_daily_movement DESC NULLS LAST;


-- ---------------------------------------------------------------------------
-- 7d: Count of SCD2 history records per account (chain length)
-- ---------------------------------------------------------------------------
-- Useful for monitoring: excessively long chains may need compaction.
-- ---------------------------------------------------------------------------
SELECT
    ah.account_id,
    a.account_holder,
    COUNT(*)                                         AS history_chain_length,
    MIN(ah.valid_from)                               AS earliest_record,
    MAX(CASE WHEN ah.is_current THEN ah.valid_from END) AS latest_state_since,
    MAX(CASE WHEN ah.is_current THEN ah.balance END)    AS current_balance
FROM account_history ah
JOIN accounts a ON a.account_id = ah.account_id
GROUP BY ah.account_id, a.account_holder
ORDER BY history_chain_length DESC;
