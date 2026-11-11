# Project 3: SaaS MRR Waterfall Analysis

## Business Context

You are the analytics engineer at **CloudSync**, a B2B SaaS company offering a project-management platform to mid-market and enterprise customers. Leadership needs a **Monthly Recurring Revenue (MRR) Waterfall** — a month-over-month breakdown that classifies every dollar of MRR movement into standard SaaS categories. The CFO uses this waterfall in board decks, investor updates, and forecasting models.

Subscriptions are billed monthly. Customers can upgrade to a higher-tier plan, downgrade to a lower-tier plan, cancel entirely, or reactivate after a previous cancellation. Revenue recognition follows the subscription's effective dates, not invoice dates.

The waterfall must reconcile perfectly: **Beginning MRR + New + Expansion − Contraction − Churn + Reactivation = Ending MRR** for every month.

---

## Objectives

1. Design a normalized schema that captures subscriptions, plans, and billing events over time.
2. Build a SQL pipeline that computes each customer's MRR for every month they are active.
3. Classify month-over-month MRR movements into the five standard categories:
   - **New MRR** — Revenue from a brand-new customer (first-ever subscription).
   - **Expansion MRR** — Increase in MRR from an existing customer (plan upgrade or seat addition).
   - **Contraction MRR** — Decrease in MRR from an existing customer (plan downgrade or seat removal).
   - **Churn MRR** — Revenue lost when a customer cancels entirely (MRR drops to $0).
   - **Reactivation MRR** — Revenue from a customer who previously churned and has returned.
4. Produce a final MRR waterfall summary table grouped by month.
5. Validate that the waterfall balances: `beginning_mrr + new + expansion - contraction - churn + reactivation = ending_mrr`.

---

## Input Schema Description

### `plans`
Stores the product tiers available for subscription.

| Column       | Type           | Description                        |
|--------------|----------------|------------------------------------|
| plan_id      | INT (PK)       | Unique plan identifier             |
| plan_name    | VARCHAR(100)   | Human-readable plan name           |
| monthly_price| DECIMAL(10,2)  | Monthly recurring price in USD     |

### `subscriptions`
Represents each customer's subscription lifecycle. A single customer may have multiple rows if they cancel and later reactivate.

| Column           | Type           | Description                                      |
|------------------|----------------|--------------------------------------------------|
| subscription_id  | INT (PK)       | Unique subscription identifier                   |
| customer_id      | INT            | Customer identifier                              |
| plan_id          | INT (FK)       | Current plan                                     |
| started_at       | DATE           | Subscription start date                          |
| canceled_at      | DATE NULL      | Cancellation effective date (NULL if active)      |
| status           | VARCHAR(20)    | `active`, `canceled`                             |

### `billing_events`
An append-only log of every billing-related event: new subscription, plan change, cancellation, reactivation.

| Column           | Type           | Description                                      |
|------------------|----------------|--------------------------------------------------|
| event_id         | INT (PK)       | Unique event identifier                          |
| subscription_id  | INT (FK)       | Linked subscription                              |
| customer_id      | INT            | Customer identifier                              |
| event_type       | VARCHAR(30)    | `new`, `upgrade`, `downgrade`, `cancellation`, `reactivation` |
| old_plan_id      | INT NULL       | Previous plan (NULL for `new` events)            |
| new_plan_id      | INT NULL       | New plan (NULL for `cancellation` events)        |
| old_mrr          | DECIMAL(10,2)  | MRR before this event                            |
| new_mrr          | DECIMAL(10,2)  | MRR after this event                             |
| event_date       | DATE           | Date the event takes effect                      |

---

## Expected Deliverables

1. **`schema.sql`** — DDL statements creating all three tables with appropriate constraints and keys.
2. **`seed_data.sql`** — Realistic mock data covering all five MRR movement types across at least 6 months, with enough volume (30-50+ rows per main table) to demonstrate edge cases.
3. **`solution.sql`** — A fully commented reference solution that:
   - Generates a month spine covering the data range.
   - Computes per-customer monthly MRR snapshots.
   - Classifies month-over-month MRR deltas into the five movement categories.
   - Aggregates into a final waterfall summary.
   - Includes a reconciliation check.

---

## Bonus Challenges

1. **Cohort Retention Curve** — Extend the waterfall to show MRR retention by signup cohort (month of first subscription).
2. **Net Revenue Retention (NRR)** — Calculate trailing-12-month NRR percentage: `(Beginning MRR + Expansion − Contraction − Churn) / Beginning MRR`.
3. **Quick Ratio** — Compute the SaaS Quick Ratio: `(New + Expansion + Reactivation) / (Contraction + Churn)` per month.
4. **Logo vs. Dollar Churn** — Differentiate between logo churn (count of customers lost) and dollar churn (revenue lost), since they often tell different stories.
5. **Mid-Month Plan Changes** — Handle the pro-ration scenario where a customer upgrades mid-month and only a partial delta applies to the current month.
