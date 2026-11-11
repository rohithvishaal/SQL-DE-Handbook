export type NonDuckDbEngine = 'snowflake' | 'bigquery' | 'databricks' | 'postgres-jsonb';
export type SqlEngine = 'duckdb' | NonDuckDbEngine;

export interface DialectPlatformInfo {
  engine: NonDuckDbEngine;
  label: string;
  reason: string;
  platformName: string;
  url: string;
  ctaLabel: string;
  altUrl?: string;
  altLabel?: string;
}

export const DIALECT_PLATFORMS: Readonly<Record<NonDuckDbEngine, DialectPlatformInfo>> = {
  snowflake: {
    engine: 'snowflake',
    label: 'Snowflake',
    reason:
      'Uses Snowflake-specific syntax (LATERAL FLATTEN, DIV0, or :path colon notation) unsupported in browser DuckDB-Wasm.',
    platformName: 'Snowflake Trial',
    url: 'https://signup.snowflake.com/',
    ctaLabel: 'Open Snowflake Trial ↗',
  },
  bigquery: {
    engine: 'bigquery',
    label: 'Google BigQuery',
    reason:
      'Uses BigQuery-specific syntax (SAFE_DIVIDE, JSON_VALUE, or UNNEST WITH OFFSET) unsupported in browser DuckDB-Wasm.',
    platformName: 'BigQuery Studio',
    url: 'https://console.cloud.google.com/bigquery',
    ctaLabel: 'Open BigQuery Console ↗',
  },
  databricks: {
    engine: 'databricks',
    label: 'Databricks (Spark SQL)',
    reason:
      'Uses Spark SQL / Delta syntax (EXPLODE, EXPLODE_OUTER, TRY_DIVIDE, or CLUSTER BY) unsupported in browser DuckDB-Wasm.',
    platformName: 'Databricks Free Edition',
    url: 'https://www.databricks.com/product/free-edition',
    ctaLabel: 'Open Databricks Free Edition ↗',
  },
  'postgres-jsonb': {
    engine: 'postgres-jsonb',
    label: 'PostgreSQL (JSONB)',
    reason:
      'Uses PostgreSQL-only JSONB operators and table functions (jsonb_array_elements, ->, ->>) outside DuckDB-Wasm SQL.',
    platformName: 'Crunchy Postgres Playground',
    url: 'https://www.crunchydata.com/developers/playground',
    ctaLabel: 'Open Postgres Playground ↗',
    altUrl: 'https://www.db-fiddle.com/',
    altLabel: 'DB Fiddle ↗',
  },
};

export function canExecuteInDuckDb(engine: SqlEngine): engine is 'duckdb' {
  return engine === 'duckdb';
}

export type GuardedExecution<T> =
  | { executed: true; value: T }
  | { executed: false; reason: string; platformUrl: string };

export function executeIfDuckDb<T>(engine: SqlEngine, runner: () => T): GuardedExecution<T> {
  if (!canExecuteInDuckDb(engine)) {
    const info = DIALECT_PLATFORMS[engine];
    return {
      executed: false,
      reason: info.reason,
      platformUrl: info.url,
    };
  }
  return {
    executed: true,
    value: runner(),
  };
}
