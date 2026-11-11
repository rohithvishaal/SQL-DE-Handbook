import type { CardKind, ReviewRating } from './retentionStore';

export const REVIEW_RATING_OPTIONS: ReadonlyArray<{ rating: ReviewRating; label: string; hint: string }> = [
  { rating: 1, label: 'Again', hint: '10m' },
  { rating: 2, label: 'Hard', hint: '1d' },
  { rating: 3, label: 'Good', hint: '4d' },
  { rating: 4, label: 'Easy', hint: '9d' },
];

export function formatIntervalDays(days: number): string {
  if (days < 1) return `${Math.round(days * 24 * 60)}m`;
  return `${days}d`;
}

export interface RecallCardMeta {
  id: string;
  moduleId: string;
  kind: CardKind;
  prompt: string;
  answer: string;
}

export interface PlacementQuestion {
  id: string;
  cardId: string;
  moduleId: string;
  prompt: string;
  options: readonly [string, string, string, string];
  correctIndex: 0 | 1 | 2 | 3;
  explanation: string;
}

export const PLACEMENT_QUESTIONS: readonly PlacementQuestion[] = [
  {
    id: 'pq-1',
    cardId: 'm1-having-aggregate-repeat',
    moduleId: 'm1',
    prompt: 'In ANSI SQL, how must you filter groups by an average when AVG(row_count) AS avg_rows is in SELECT?',
    options: [
      'Repeat AVG(row_count) inside HAVING AVG(row_count) < 10000',
      'Reference HAVING avg_rows < 10000 directly',
      'Move AVG(row_count) < 10000 into WHERE',
      'Use QUALIFY avg_rows < 10000 before GROUP BY',
    ],
    correctIndex: 0,
    explanation: 'SELECT aliases are not in scope inside HAVING in ANSI SQL, PostgreSQL, or DuckDB.',
  },
  {
    id: 'pq-2',
    cardId: 'diag-m1-null-in',
    moduleId: 'm1',
    prompt: 'What happens when col NOT IN (1, 2, NULL) executes against non-null rows?',
    options: [
      'It ignores the NULL and returns rows other than 1 and 2',
      'It evaluates to UNKNOWN for every row and returns zero rows',
      'It raises a runtime null-pointer exception',
      'It converts NULL to 0 before comparing',
    ],
    correctIndex: 1,
    explanation: 'x <> NULL yields UNKNOWN, turning the AND chain UNKNOWN and filtering out all rows. Prefer NOT EXISTS.',
  },
  {
    id: 'pq-3',
    cardId: 'diag-m2-last-value-frame',
    moduleId: 'm2',
    prompt: 'Why does LAST_VALUE(val) OVER (ORDER BY ts) often return the current row value instead of the partition end?',
    options: [
      'Because ORDER BY reverses partition scan direction',
      'Because the default frame with ORDER BY ends at CURRENT ROW',
      'Because LAST_VALUE ignores NULLs by default',
      'Because GROUP BY is required alongside window frames',
    ],
    correctIndex: 1,
    explanation: 'When ORDER BY is present, the default window frame is RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW.',
  },
  {
    id: 'pq-4',
    cardId: 'diag-m2-rows-range',
    moduleId: 'm2',
    prompt: 'Which frame ensures duplicate ORDER BY timestamps are counted row-by-row instead of lumped as peers?',
    options: [
      'RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW',
      'GROUPS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING',
      'ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW',
      'PARTITION BY ORDER BY STRICT',
    ],
    correctIndex: 2,
    explanation: 'ROWS operates on physical row offsets whereas RANGE groups equal ORDER BY peer values together.',
  },
  {
    id: 'pq-5',
    cardId: 'diag-m3-scd2-overlap',
    moduleId: 'm3',
    prompt: 'Which window function computes the valid_to timestamp of each SCD Type 2 version without a self-join?',
    options: [
      'LAG(updated_at) OVER (PARTITION BY entity_id ORDER BY updated_at)',
      'LEAD(updated_at) OVER (PARTITION BY entity_id ORDER BY updated_at)',
      'FIRST_VALUE(updated_at) OVER (PARTITION BY entity_id)',
      'NTILE(2) OVER (ORDER BY updated_at)',
    ],
    correctIndex: 1,
    explanation: 'LEAD looks ahead to the next state change timestamp to close the current version interval.',
  },
  {
    id: 'pq-6',
    cardId: 'diag-m4-snowflake-flatten',
    moduleId: 'm4',
    prompt: 'In Snowflake, which LATERAL FLATTEN argument preserves parent rows whose array is NULL or empty?',
    options: [
      'LATERAL FLATTEN(input => col, STRICT => FALSE)',
      'LATERAL FLATTEN(input => col, OUTER => TRUE)',
      'CROSS JOIN FLATTEN(col, NULLS FIRST)',
      'LEFT FLATTEN(col) KEEP EMPTY',
    ],
    correctIndex: 1,
    explanation: 'OUTER => TRUE behaves like a LEFT JOIN for array flattening instead of dropping empty arrays.',
  },
  {
    id: 'pq-7',
    cardId: 'diag-m5-sargable-date',
    moduleId: 'm5',
    prompt: 'Which filter keeps predicates SARGable so partition/zone-map pruning still fires on an indexed event_ts column?',
    options: [
      "WHERE DATE_TRUNC('day', event_ts) = DATE '2026-01-15'",
      "WHERE CAST(event_ts AS VARCHAR) LIKE '2026-01-15%'",
      "WHERE event_ts >= TIMESTAMP '2026-01-15 00:00:00' AND event_ts < TIMESTAMP '2026-01-16 00:00:00'",
      "WHERE EXTRACT(DAY FROM event_ts) = 15",
    ],
    correctIndex: 2,
    explanation: 'Wrapping the indexed column in a function blocks min/max pruning; use half-open range predicates instead.',
  },
  {
    id: 'pq-8',
    cardId: 'diag-m6-top-n',
    moduleId: 'm6',
    prompt: 'Which ranking function assigns consecutive ranks (1, 1, 2) on ties so top-3 categories keep tied leaders?',
    options: [
      'ROW_NUMBER()',
      'RANK()',
      'DENSE_RANK()',
      'PERCENT_RANK()',
    ],
    correctIndex: 2,
    explanation: 'DENSE_RANK leaves no gaps after ties (1, 1, 2), whereas RANK skips to 3 and ROW_NUMBER breaks ties.',
  },
];

export const CARD_CATALOG: Record<string, RecallCardMeta> = {
  'm1-having-aggregate-repeat': {
    id: 'm1-having-aggregate-repeat',
    moduleId: 'm1',
    kind: 'cloze',
    prompt: 'Filter aggregated groups in ANSI SQL without relying on SELECT aliases:\nSELECT source_system, AVG(row_count) AS avg_rows FROM daily_loads GROUP BY source_system _____',
    answer: 'HAVING AVG(row_count) < 10000',
  },
  'diag-m1-null-in': {
    id: 'diag-m1-null-in',
    moduleId: 'm1',
    kind: 'trap',
    prompt: 'Why should data pipelines avoid col NOT IN (subquery) when NULLs can appear?',
    answer: 'Any NULL turns col NOT IN (...) into UNKNOWN, returning 0 rows. Use NOT EXISTS instead.',
  },
  'diag-m2-last-value-frame': {
    id: 'diag-m2-last-value-frame',
    moduleId: 'm2',
    kind: 'trap',
    prompt: 'Why does LAST_VALUE(x) OVER (PARTITION BY p ORDER BY ts) stop at the current row by default?',
    answer: 'With ORDER BY, the implicit default frame is RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW. Add ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING.',
  },
  'diag-m2-rows-range': {
    id: 'diag-m2-rows-range',
    moduleId: 'm2',
    kind: 'cloze',
    prompt: 'Frame clause preventing duplicate timestamps from grouping as peers:',
    answer: 'ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW',
  },
  'diag-m3-scd2-overlap': {
    id: 'diag-m3-scd2-overlap',
    moduleId: 'm3',
    kind: 'cloze',
    prompt: 'Derive valid_to in an SCD Type 2 history table via window lookahead:',
    answer: 'LEAD(updated_at) OVER (PARTITION BY entity_id ORDER BY updated_at)',
  },
  'diag-m4-snowflake-flatten': {
    id: 'diag-m4-snowflake-flatten',
    moduleId: 'm4',
    kind: 'dialect',
    prompt: 'Snowflake option inside LATERAL FLATTEN to retain parent rows with NULL/empty arrays:',
    answer: 'LATERAL FLATTEN(input => col, OUTER => TRUE)',
  },
  'diag-m5-sargable-date': {
    id: 'diag-m5-sargable-date',
    moduleId: 'm5',
    kind: 'trap',
    prompt: 'Write a SARGable single-day filter on event_ts without breaking partition pruning:',
    answer: "event_ts >= TIMESTAMP '2026-01-15 00:00:00' AND event_ts < TIMESTAMP '2026-01-16 00:00:00'",
  },
  'diag-m6-top-n': {
    id: 'diag-m6-top-n',
    moduleId: 'm6',
    kind: 'cloze',
    prompt: 'Window ranking function keeping tied leaders with gapless rank integers (1, 1, 2):',
    answer: 'DENSE_RANK() OVER (PARTITION BY category ORDER BY total_revenue DESC)',
  },
  'm3-pg-jsonb-lateral': {
    id: 'm3-pg-jsonb-lateral',
    moduleId: 'm3',
    kind: 'dialect',
    prompt: 'PostgreSQL LATERAL JSONB clause preserving parent rows with empty items arrays:',
    answer: "LEFT JOIN LATERAL jsonb_array_elements(e.payload -> 'items') AS item(value) ON TRUE",
  },
  'm4-bq-safe-divide': {
    id: 'm4-bq-safe-divide',
    moduleId: 'm4',
    kind: 'dialect',
    prompt: 'BigQuery built-in division helper returning NULL cleanly on zero denominator:',
    answer: 'SAFE_DIVIDE(total_revenue, total_orders)',
  },
  'm4-db-explode-outer': {
    id: 'm4-db-explode-outer',
    moduleId: 'm4',
    kind: 'dialect',
    prompt: 'Databricks Spark SQL array explosion preserving NULL/empty array rows:',
    answer: 'LATERAL VIEW EXPLODE_OUTER(line_items) t AS line_item',
  },
};
