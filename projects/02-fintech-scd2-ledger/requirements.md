# Project 2: FinTech SCD2 Ledger — Account Balance Tracking with Full Audit Trail

## Business Context

A fast-growing FinTech company operates a digital wallet and payments platform serving millions of users. Regulatory compliance (SOX, PCI-DSS) requires a **complete, immutable audit trail** of every account balance change. The platform must support:

- **Real-time balance inquiries** — users see their current balance instantly.
- **Point-in-time balance reconstruction** — auditors can query what any account's balance was at any historical moment.
- **Out-of-order transaction handling** — payment processors, ACH networks, and card networks submit settlement files with **variable latency** (minutes to days), meaning transactions frequently arrive out of chronological order.
- **Reconciliation** — at end-of-day (EOD), the sum of all posted transactions for an account must match the account's current balance. Discrepancies must be flagged and investigated.

The data engineering team has chosen **Slowly Changing Dimension Type 2 (SCD2)** to track balance history because it preserves every historical state without overwriting prior records, enabling both current-state queries and historical lookups from a single table.

> [!IMPORTANT]
> Out-of-order transactions are the core challenge. A transaction dated Monday may arrive on Wednesday, **after** Tuesday's transactions have already been processed. The SCD2 pipeline must retroactively adjust the history chain when this happens.

---

## Objectives

1. **Design a normalized schema** with `accounts`, `transactions`, and `account_history` (SCD2) tables that supports both current-state and historical queries.
2. **Implement an SCD2 MERGE pipeline** that processes incoming transactions and maintains the `account_history` table with correct `valid_from`, `valid_to`, and `is_current` flags.
3. **Handle out-of-order (late-arriving) transactions** by retroactively inserting history records and adjusting the validity windows of surrounding records.
4. **Build reconciliation queries** that compare the running sum of transactions against the stored account balance, flagging any discrepancies.
5. **Demonstrate point-in-time queries** that reconstruct an account's balance at any arbitrary timestamp.
6. **Ensure idempotency** — reprocessing the same transaction batch must not create duplicate history records or corrupt balances.

---

## Input Schema Description

### `accounts`
The master account table holding current-state information for each financial account.

| Column | Type | Description |
|---|---|---|
| `account_id` | INT (PK) | Unique account identifier |
| `account_number` | VARCHAR(20) | External-facing account number |
| `account_holder` | VARCHAR(100) | Name of the account holder |
| `account_type` | VARCHAR(20) | `checking`, `savings`, `investment` |
| `current_balance` | DECIMAL(15,2) | Current balance (updated on each transaction) |
| `currency` | CHAR(3) | ISO 4217 currency code (e.g., `USD`) |
| `status` | VARCHAR(10) | `active`, `frozen`, `closed` |
| `opened_at` | TIMESTAMP | Account opening date |
| `updated_at` | TIMESTAMP | Last modification timestamp |

### `transactions`
Raw transaction ledger — every credit/debit ever posted.

| Column | Type | Description |
|---|---|---|
| `transaction_id` | INT (PK) | Unique transaction identifier |
| `account_id` | INT (FK) | Reference to `accounts` |
| `transaction_type` | VARCHAR(10) | `credit` or `debit` |
| `amount` | DECIMAL(15,2) | Transaction amount (always positive) |
| `transaction_date` | TIMESTAMP | When the transaction *actually occurred* |
| `posted_date` | TIMESTAMP | When the transaction was *received/processed* |
| `description` | VARCHAR(200) | Human-readable description |
| `reference_id` | VARCHAR(50) | External reference (check number, wire ID, etc.) |
| `source_system` | VARCHAR(30) | Originating system (`ACH`, `WIRE`, `CARD`, `INTERNAL`) |
| `created_at` | TIMESTAMP | Row insert timestamp |

> [!NOTE]
> The gap between `transaction_date` and `posted_date` is where out-of-order issues arise. A transaction with `transaction_date = '2024-01-15'` might have `posted_date = '2024-01-17'`, arriving after the Jan 16 batch has already run.

### `account_history` (SCD Type 2)
Tracks every state of an account's balance over time.

| Column | Type | Description |
|---|---|---|
| `history_id` | INT (PK) | Surrogate key |
| `account_id` | INT (FK) | Reference to `accounts` |
| `balance` | DECIMAL(15,2) | Account balance during this period |
| `transaction_id` | INT (FK, nullable) | Transaction that caused this state (NULL for initial state) |
| `valid_from` | TIMESTAMP | Start of this record's validity (inclusive) |
| `valid_to` | TIMESTAMP | End of this record's validity (exclusive); `'9999-12-31'` for current |
| `is_current` | BOOLEAN | `TRUE` if this is the active record |
| `created_at` | TIMESTAMP | Row insert timestamp |
| `modified_at` | TIMESTAMP | Last modification timestamp |

---

## Expected Deliverables

1. **`schema.sql`** — DDL to create all three tables with appropriate constraints, indexes, and foreign keys.
2. **`seed_data.sql`** — Realistic seed data with 30–50 rows per main table, including deliberate out-of-order transactions to exercise edge cases.
3. **`solution.sql`** — Full reference solution containing:
   - A `MERGE`-based SCD2 update procedure that processes new transactions into `account_history`.
   - Out-of-order transaction handling logic that retroactively adjusts history windows.
   - A reconciliation query that validates `current_balance` against the sum of transactions.
   - A point-in-time balance lookup query.
   - An idempotency check to prevent duplicate processing.

---

## Bonus Challenges

1. **Multi-currency support** — Extend the schema to handle accounts in different currencies and add FX conversion rates to reconciliation.
2. **Balance snapshots** — Create a daily snapshot table that materializes EOD balances for fast historical reporting without scanning the full SCD2 chain.
3. **Concurrent transaction ordering** — When two transactions share the exact same `transaction_date`, define and implement a deterministic tie-breaking rule (e.g., by `transaction_id`).
4. **Soft deletes and reversals** — Model transaction reversals (chargebacks, returned ACH) as new transactions that reference the original, and track the balance impact through SCD2.
5. **Gap detection** — Write a query that finds gaps or overlaps in `account_history` validity ranges, which would indicate data corruption.
6. **Performance optimization** — Add covering indexes and partitioning strategies for tables exceeding 1 billion rows, and explain the trade-offs.
