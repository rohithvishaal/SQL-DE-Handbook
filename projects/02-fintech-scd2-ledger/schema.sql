-- ============================================================================
-- Project 2: FinTech SCD2 Ledger — Schema Definition
-- ============================================================================
-- ANSI SQL DDL for a FinTech account balance tracking system using
-- Slowly Changing Dimension Type 2 (SCD2) for full audit trail.
-- ============================================================================

-- ============================================================================
-- 1. ACCOUNTS — Master account table (current state)
-- ============================================================================
CREATE TABLE accounts (
    account_id        INT           PRIMARY KEY,
    account_number    VARCHAR(20)   NOT NULL UNIQUE,
    account_holder    VARCHAR(100)  NOT NULL,
    account_type      VARCHAR(20)   NOT NULL
                      CHECK (account_type IN ('checking', 'savings', 'investment')),
    current_balance   DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    currency          CHAR(3)       NOT NULL DEFAULT 'USD',
    status            VARCHAR(10)   NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active', 'frozen', 'closed')),
    opened_at         TIMESTAMP     NOT NULL,
    updated_at        TIMESTAMP     NOT NULL
);

-- Index for lookups by account number (common in API layer)
CREATE INDEX idx_accounts_account_number ON accounts (account_number);

-- Index for filtering by status (operational dashboards)
CREATE INDEX idx_accounts_status ON accounts (status);


-- ============================================================================
-- 2. TRANSACTIONS — Raw transaction ledger (append-only)
-- ============================================================================
CREATE TABLE transactions (
    transaction_id    INT           PRIMARY KEY,
    account_id        INT           NOT NULL,
    transaction_type  VARCHAR(10)   NOT NULL
                      CHECK (transaction_type IN ('credit', 'debit')),
    amount            DECIMAL(15,2) NOT NULL
                      CHECK (amount > 0),
    transaction_date  TIMESTAMP     NOT NULL,   -- when the txn actually occurred
    posted_date       TIMESTAMP     NOT NULL,   -- when we received/processed it
    description       VARCHAR(200),
    reference_id      VARCHAR(50),
    source_system     VARCHAR(30)   NOT NULL
                      CHECK (source_system IN ('ACH', 'WIRE', 'CARD', 'INTERNAL')),
    created_at        TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_txn_account
        FOREIGN KEY (account_id) REFERENCES accounts (account_id)
);

-- Composite index for fetching an account's transactions in date order
CREATE INDEX idx_txn_account_date ON transactions (account_id, transaction_date);

-- Index for reconciliation: posted_date range scans
CREATE INDEX idx_txn_posted_date ON transactions (posted_date);

-- Index for idempotency checks by reference_id
CREATE INDEX idx_txn_reference ON transactions (reference_id);

-- Index for source system filtering (batch processing by source)
CREATE INDEX idx_txn_source ON transactions (source_system, posted_date);


-- ============================================================================
-- 3. ACCOUNT_HISTORY — SCD Type 2 balance history (audit trail)
-- ============================================================================
-- Each row represents a balance state for an account over a time window.
-- - valid_from (inclusive) to valid_to (exclusive) defines the window.
-- - is_current = TRUE marks the active/latest record.
-- - valid_to = '9999-12-31 23:59:59' is the sentinel for "still current".
-- ============================================================================
CREATE TABLE account_history (
    history_id        INT           PRIMARY KEY,
    account_id        INT           NOT NULL,
    balance           DECIMAL(15,2) NOT NULL,
    transaction_id    INT,          -- NULL for the initial opening balance record
    valid_from        TIMESTAMP     NOT NULL,
    valid_to          TIMESTAMP     NOT NULL DEFAULT '9999-12-31 23:59:59',
    is_current        BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_hist_account
        FOREIGN KEY (account_id) REFERENCES accounts (account_id),
    CONSTRAINT fk_hist_transaction
        FOREIGN KEY (transaction_id) REFERENCES transactions (transaction_id),
    CONSTRAINT chk_valid_range
        CHECK (valid_to > valid_from)
);

-- Critical index: point-in-time lookups ("what was the balance at time X?")
CREATE INDEX idx_hist_account_time ON account_history (account_id, valid_from, valid_to);

-- Index for finding the current record quickly
CREATE INDEX idx_hist_current ON account_history (account_id, is_current)
    ;  -- In production, add WHERE is_current = TRUE as a partial index if supported

-- Index for joining back to the causal transaction
CREATE INDEX idx_hist_txn ON account_history (transaction_id);
