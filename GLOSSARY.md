# Data Engineering SQL Handbook

Domain language for the interactive Data Engineering SQL Handbook: curriculum structure, spaced-repetition learning mechanics, live SQL verification, and minimalist progress telemetry.

## Language

### Curriculum & Content

**Handbook Module**:
A curated curriculum unit covering a cohesive Data Engineering SQL area across cheatsheets, exercises, interview problems, or projects.
_Avoid_: Lesson, Chapter, Course unit

**Pipeline Checkpoint**:
A distinct, verifiable intermediate or final SQL stage inside a capstone project validated against that project's seeded dataset.
_Avoid_: Sub-task, Step, Milestone task

**Dialect Block**:
A SQL snippet written for a non-DuckDB engine (Snowflake, Google BigQuery, Databricks, or PostgreSQL-only `JSONB`) rendered non-executable with an incompatibility notice, an outbound platform link, and optional Cloze recall.
_Avoid_: Read-only snippet, External code box

### Spaced Repetition & Recall

**Recall Card**:
A scheduled unit of active review—representing a syntax concept, Cloze drill, edge-case trap, or solved problem—tracked across spaced repetitions.
_Avoid_: Flashcard, Queue item, Memory card

**Cloze Drill**:
An inline SQL snippet with specific clauses or dialect keywords masked until the learner recalls or types them before rating recall confidence.
_Avoid_: Blur box, Fill-in-the-blank

**Due Queue**:
The active list of enrolled Recall Cards whose next review timestamp has arrived or passed.
_Avoid_: Backlog, Review pile, Todo queue

**Memory Strength**:
A continuous `0–100%` estimate of current recall probability based on card stability and elapsed time, grouped cleanly into **Strong**, **Fading**, and **Due**.
_Avoid_: Retention health, Progress percentage, Mastery bar

**Review Rating**:
The four-grade self-evaluation (`Again`, `Hard`, `Good`, `Easy`) chosen after revealing a Recall Card that computes the next review interval.
_Avoid_: Confidence vote, Difficulty button

### Verification, Integrity & Telemetry

**Solo Pass**:
Independent verification of an exercise query, interview problem, or Pipeline Checkpoint without revealing the solution beforehand, earning full XP and normal spacing.
_Avoid_: Unassisted solve, Clean run

**Guided Review**:
Completing or grading an exercise, interview challenge, or Cloze Drill after revealing the answer, awarding reduced XP and scheduling an early `1-day` follow-up review.
_Avoid_: Peek, Cheat, Assisted pass

**Result-Set Diff**:
Structured comparison between a learner's actual DuckDB query output and the expected output using numeric float tolerance and prompt-driven order sensitivity.
_Avoid_: String match, Text diff

**Interview Session**:
A timed practice mode for an interview problem featuring a target countdown, progressive hint reveals, and gated Brute-Force versus Optimal walkthroughs.
_Avoid_: Exam mode, Timed quiz

**Consistency Streak**:
Consecutive calendar days in which the learner completes their daily review or query goal, protected up to two missed days by earned **Streak Freezes**.
_Avoid_: Login streak, Daily counter

**Today Hub**:
The root entry workspace displaying the Due Queue summary, per-module Memory Strength, active Consistency Streak, XP total, and quick-resume links.
_Avoid_: Home dashboard, Landing page
