---
status: accepted
---

# Client-Only Retention Persistence with JSON Backup Instead of User Auth

All spaced-repetition schedules, Memory Strength decay calculations, Consistency Streaks, Streak Freezes, XP telemetry, and solved query snapshots will persist exclusively in client-side browser storage (`IndexedDB` / `localStorage`) with one-click JSON export and import, with zero user authentication or remote database backend. Adding accounts and server sync later changes the data ownership model, static-hosting footprint, and onboarding UX, so trading cross-device automatic sync for zero-friction static deployment and instant cold load is an intentional architectural boundary.
