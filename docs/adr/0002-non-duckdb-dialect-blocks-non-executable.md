---
status: accepted
---

# Keep Non-DuckDB Dialect Blocks Strictly Non-Executable

SQL snippets targeting Snowflake (`LATERAL FLATTEN`, `DIV0`), Google BigQuery (`SAFE_DIVIDE`, `JSON_VALUE`), Databricks (Spark SQL `EXPLODE`), or PostgreSQL-only extensions (`jsonb_array_elements`) will render strictly non-executable inside the browser workbench with an explicit notice explaining why DuckDB-Wasm cannot execute them and an outbound link to the target platform's console/playground (while optionally allowing Cloze syntax recall). We rejected building fragile regex/AST SQL transpilers or hiding platform differences so learners build authentic multi-dialect intuition rather than debugging fake emulation bugs; reversing this later would require rewriting both content extraction and UI component contracts.
