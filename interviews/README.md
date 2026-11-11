# Module 6: FAANG / Big Tech Interview Masterclass

> [!IMPORTANT]
> This module contains **15 real-world SQL interview problems** commonly asked at top tech companies. Each problem is self-contained with schema, sample data, brute-force and optimal solutions, and interviewer follow-ups.

---

## 🎯 Who Is This For?

- Data Engineers preparing for FAANG / Big Tech interviews
- Analytics Engineers brushing up on advanced SQL patterns
- Anyone who wants to go beyond LeetCode-style SQL into production-realistic scenarios

---

## 📋 Problem Index

| # | Problem | Difficulty | Core Pattern | Key Companies |
|---|---------|-----------|--------------|---------------|
| 01 | [Active User Retention & Cohort Churn](01-cohort-retention.md) | 🔴 Hard | Self-joins, date arithmetic, cohort matrices | Meta, Netflix, Spotify, Airbnb |
| 02 | [Consecutive Days Active / Streak Analysis](02-consecutive-streaks.md) | 🟡 Medium | Gaps & Islands, ROW_NUMBER differencing | Snapchat, Meta, Spotify, LinkedIn |
| 03 | [Top N Products per Category](03-top-n-per-category.md) | 🟡 Medium | Window functions, RANK vs DENSE_RANK | Amazon, Walmart, Instacart, DoorDash |
| 04 | [Overlapping Bookings / Resource Contention](04-overlapping-intervals.md) | 🔴 Hard | Interval overlap detection, running max | Airbnb, Google, Uber, Booking.com |
| 05 | [Marketing Attribution Modeling](05-attribution-modeling.md) | 🔴 Hard | FIRST_VALUE, LAST_VALUE, fractional allocation | Google, Meta, Pinterest, Snap |
| 06 | [Circular / Ring Transactions (Fraud)](06-circular-transactions.md) | 🔴 Hard | Recursive CTEs, graph traversal in SQL | PayPal, Stripe, Square, Goldman Sachs |
| 07 | [Unmatched Records Across Massive Tables](07-unmatched-records.md) | 🟡 Medium | Anti-joins, NOT EXISTS vs LEFT JOIN | Amazon, Apple, Microsoft, Google |
| 08 | [Running Total with Budget Cap](08-running-totals-budget.md) | 🟡 Medium | Window SUM, conditional cumulation | Netflix, Uber, Lyft, DoorDash |
| 09 | [Dynamic Pivot / Unpivot](09-pivot-unpivot.md) | 🟡 Medium | CASE WHEN pivot, CROSS JOIN UNNEST | Microsoft, Amazon, Salesforce, Oracle |
| 10 | [Multi-Step Event Funnel Analysis](10-event-funnel.md) | 🔴 Hard | Conditional aggregation, sessionization | Meta, Google, Airbnb, Uber, Spotify |
| 11 | [Median & Percentiles Without Built-ins](11-median-percentile.md) | 🟡 Medium | ROW_NUMBER, COUNT, self-join | Google, Meta, Amazon, Microsoft |
| 12 | [Recursive Hierarchy Rollup](12-hierarchical-rollup.md) | 🔴 Hard | Recursive CTE, tree aggregation | Google, Amazon, Salesforce, SAP |
| 13 | [Deduplication with Priority Rules & MERGE](13-dedup-merge.md) | 🟡 Medium | ROW_NUMBER partitioning, MERGE upsert | Snowflake, Databricks, Netflix, Airbnb |
| 14 | [Time-Weighted Averages (IoT/Sensor)](14-time-weighted-avg.md) | 🔴 Hard | LEAD/LAG, EXTRACT(EPOCH), weighted sum | Tesla, Honeywell, Samsara, Uptake |
| 15 | [Point-in-Time / Temporal Joins (SCD2)](15-slowly-changing-join.md) | 🔴 Hard | Range joins, SCD Type 2 lookups | Netflix, Airbnb, Stripe, Spotify |

---

## 🗂️ Difficulty Breakdown

| Difficulty | Count | Problems |
|-----------|-------|----------|
| 🟡 Medium | 7 | #02, #03, #07, #08, #09, #11, #13 |
| 🔴 Hard | 8 | #01, #04, #05, #06, #10, #12, #14, #15 |

---

## 🧠 How to Use This Module

1. **Read the Problem Statement** — understand the business scenario before writing any SQL
2. **Try the Brute Force first** — get a working solution, even if slow
3. **Study the Optimal Solution** — understand *why* it performs better
4. **Answer the Follow-Ups** — interviewers always extend the problem
5. **Review Key Takeaways** — internalize the reusable pattern

> [!TIP]
> In real interviews, **communication matters as much as the code**. Practice explaining your approach out loud before writing SQL. Start with edge cases and clarifying questions.

---

## 🔗 Pattern Cross-Reference

| Pattern | Problems |
|---------|----------|
| Window Functions (RANK, ROW_NUMBER, LEAD/LAG) | #02, #03, #08, #11, #13, #14 |
| Recursive CTEs | #06, #12 |
| Self-Joins | #01, #04, #06 |
| Gaps & Islands | #02, #04 |
| Anti-Joins / Set Difference | #07 |
| Conditional Aggregation | #05, #09, #10 |
| Date/Time Arithmetic | #01, #02, #14, #15 |
| MERGE / Upserts | #13 |
| Temporal / Range Joins | #14, #15 |

---

## 📚 Prerequisites

Before tackling these problems, ensure you are comfortable with:

- [Module 1: Quick Syntax & Foundation Cheat Sheet](../cheatsheets/01-foundations-syntax.md)
- [Module 2: Advanced Analytical SQL & Window Functions](../cheatsheets/02-window-functions.md)
- [Module 3: Production Data Engineering Patterns](../cheatsheets/03-de-patterns.md)

---

*Good luck with your interviews! 🚀*
