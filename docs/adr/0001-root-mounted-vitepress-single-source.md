---
status: accepted
---

# Mount VitePress Directly at Repository Root (Single Source of Truth)

Because all 50 Phase 1 Markdown and `.sql` files are authored cleanly at the repository root (`README.md`, `cheatsheets/`, `exercises/`, `interviews/`, `projects/`) and cross-linked for direct GitHub reading, we will mount VitePress with `srcDir: '.'` (keeping runtime config and interactive components under `.vitepress/` and exposing `index.md` as the Today Hub) instead of duplicating files into a separate `docs/` directory. Swapping to a duplicated build pipeline later is painful to reverse without breaking relative links or causing content drift, and storing site config at the root without `docs/` may otherwise surprise contributors familiar with default VitePress scaffolding.
