import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import {
  canExecuteInDuckDb,
  DIALECT_PLATFORMS,
  executeIfDuckDb,
  type NonDuckDbEngine,
} from './dialectGuard';
import DialectBlock from '../theme/components/DialectBlock.vue';
import { createMemoryFallbackStorage, createRetentionStore } from './retentionStore';

describe('Dialect Block Execution Guard & Component (Seams #2 & #3 Ticket 03)', () => {
  it('blocks DuckDB execution for Snowflake, BigQuery, Databricks, and PostgreSQL JSONB engines', () => {
    const blockedEngines: NonDuckDbEngine[] = [
      'snowflake',
      'bigquery',
      'databricks',
      'postgres-jsonb',
    ];

    expect(canExecuteInDuckDb('duckdb')).toBe(true);

    for (const engine of blockedEngines) {
      expect(canExecuteInDuckDb(engine)).toBe(false);
      const runner = vi.fn(() => 'SHOULD_NOT_RUN');
      const result = executeIfDuckDb(engine, runner);

      expect(runner).not.toHaveBeenCalled();
      expect(result).toEqual({
        executed: false,
        reason: DIALECT_PLATFORMS[engine].reason,
        platformUrl: DIALECT_PLATFORMS[engine].url,
      });
    }

    const okRunner = vi.fn(() => 'DUCKDB_OK');
    expect(executeIfDuckDb('duckdb', okRunner)).toEqual({ executed: true, value: 'DUCKDB_OK' });
    expect(okRunner).toHaveBeenCalledTimes(1);
  });

  it('renders non-executable notice, verified outbound URL, and optional Cloze Drill on DialectBlock', async () => {
    const store = createRetentionStore(createMemoryFallbackStorage(), {
      now: () => new Date('2026-11-11T10:00:00.000Z'),
    });

    const wrapper = mount(DialectBlock, {
      props: {
        engine: 'snowflake',
        cardId: 'm4-sf-flatten',
        moduleId: 'm4',
        clozePrompt: 'Preserve parent rows with NULL/empty arrays in Snowflake LATERAL FLATTEN:',
        clozePrefix: 'SELECT o.order_id, f.value FROM orders o, LATERAL ',
        clozeAnswer: 'FLATTEN(input => o.items, OUTER => TRUE)',
        clozeSuffix: ' f;',
        store,
      },
    });

    expect(wrapper.text()).toContain('Non-Executable');
    expect(wrapper.text()).toContain('Snowflake');
    expect(wrapper.text()).toContain('DuckDB-Wasm');

    const link = wrapper.get('a[data-testid="dialect-platform-link"]');
    expect(link.attributes('href')).toBe('https://signup.snowflake.com/');
    expect(link.attributes('target')).toBe('_blank');

    // Works with Cloze Drill recall without invoking any DB runner
    await wrapper.get('[data-testid="cloze-reveal-btn"]').trigger('click');
    await wrapper.get('[data-testid="cloze-rate-3"]').trigger('click');

    expect(store.getCard('m4-sf-flatten')?.kind).toBe('dialect');
    expect(store.getState().xp).toBe(15);
  });

  it('renders verified console links cleanly for BigQuery, Databricks, and PostgreSQL JSONB', () => {
    const cases: Array<{ engine: NonDuckDbEngine; url: string; sql: string }> = [
      {
        engine: 'bigquery',
        url: 'https://console.cloud.google.com/bigquery',
        sql: 'SELECT SAFE_DIVIDE(revenue, orders) FROM metrics;',
      },
      {
        engine: 'databricks',
        url: 'https://www.databricks.com/product/free-edition',
        sql: 'SELECT EXPLODE_OUTER(items) FROM events;',
      },
      {
        engine: 'postgres-jsonb',
        url: 'https://www.crunchydata.com/developers/playground',
        sql: "SELECT jsonb_array_elements(payload -> 'items') FROM events;",
      },
    ];

    for (const c of cases) {
      const w = mount(DialectBlock, { props: { engine: c.engine, sql: c.sql } });
      expect(w.get('a[data-testid="dialect-platform-link"]').attributes('href')).toBe(c.url);
      expect(w.text()).toContain(c.sql);
    }
  });
});
