import { describe, expect, it } from 'vitest';
import { createRetentionStore, type StorageLike } from './retentionStore';

function createMemoryStorage(initial: Record<string, string> = {}): StorageLike {
  const map = new Map<string, string>(Object.entries(initial));
  return {
    getItem: (key) => map.get(key) ?? null,
    setItem: (key, value) => {
      map.set(key, value);
    },
    removeItem: (key) => {
      map.delete(key);
    },
  };
}

describe('Retention & Persistence Store (Seam #1)', () => {
  const day0 = new Date('2026-11-11T10:00:00.000Z');
  const modules = [{ moduleId: 'm1', title: '01 · Foundations & NULLs' }];

  it('starts empty on cold start with zero backlog and zero XP', () => {
    const store = createRetentionStore(createMemoryStorage(), { now: () => day0 });
    const state = store.getState();

    expect(state.xp).toBe(0);
    expect(Object.keys(state.cards)).toHaveLength(0);
    expect(store.getDueCards(day0)).toEqual([]);
    expect(store.getModuleSummaries(modules, day0)).toEqual([
      {
        moduleId: 'm1',
        title: '01 · Foundations & NULLs',
        enrolledCount: 0,
        strength: 0,
        status: 'New',
        dueCount: 0,
      },
    ]);
  });

  it('schedules initial Review Ratings deterministically and awards Solo Pass XP', () => {
    const scenarios = [
      { rating: 1 as const, expectedDue: '2026-11-11T10:10:00.000Z' }, // 10 minutes
      { rating: 2 as const, expectedDue: '2026-11-12T10:00:00.000Z' }, // 1 day
      { rating: 3 as const, expectedDue: '2026-11-15T10:00:00.000Z' }, // 4 days
      { rating: 4 as const, expectedDue: '2026-11-20T10:00:00.000Z' }, // 9 days
    ];

    for (const s of scenarios) {
      const store = createRetentionStore(createMemoryStorage(), { now: () => day0 });
      const res = store.submitReview(
        {
          cardId: `card-${s.rating}`,
          moduleId: 'm1',
          kind: 'cloze',
          rating: s.rating,
        },
        day0,
      );

      expect(res.xpAwarded).toBe(15);
      expect(res.card.nextDueAt).toBe(s.expectedDue);
      expect(res.card.lastOutcome).toBe('solo_pass');
      expect(store.getState().xp).toBe(15);
    }
  });

  it('expands intervals on repeated Good reviews and resets stability on lapse', () => {
    const store = createRetentionStore(createMemoryStorage(), { now: () => day0 });
    store.submitReview({ cardId: 'c1', moduleId: 'm1', kind: 'cloze', rating: 3 }, day0);

    const day4 = new Date('2026-11-15T10:00:00.000Z');
    const second = store.submitReview({ cardId: 'c1', moduleId: 'm1', kind: 'cloze', rating: 3 }, day4);
    expect(second.card.reps).toBe(2);
    expect(second.intervalDays).toBeGreaterThan(4);
    expect(second.card.nextDueAt).toBe('2026-11-24T10:00:00.000Z'); // +9 days

    const day13 = new Date('2026-11-24T10:00:00.000Z');
    const lapsed = store.submitReview({ cardId: 'c1', moduleId: 'm1', kind: 'cloze', rating: 1 }, day13);
    expect(lapsed.card.reps).toBe(0);
    expect(lapsed.card.lapses).toBe(1);
    expect(lapsed.card.nextDueAt).toBe('2026-11-24T10:10:00.000Z');
  });

  it('downgrades Guided Review to ~20% XP and caps follow-up interval at 1 day', () => {
    const store = createRetentionStore(createMemoryStorage(), { now: () => day0 });
    const res = store.submitReview(
      {
        cardId: 'q1',
        moduleId: 'm1',
        kind: 'query',
        rating: 4, // Easy cannot skip past 1 day when revealed first
        outcome: 'guided_review',
      },
      day0,
    );

    expect(res.xpAwarded).toBe(8); // 20% of 40 base XP
    expect(res.intervalDays).toBe(1);
    expect(res.card.nextDueAt).toBe('2026-11-12T10:00:00.000Z');
    expect(res.card.lastOutcome).toBe('guided_review');
  });

  it('orders Due Queue chronologically as cards become overdue', () => {
    const store = createRetentionStore(createMemoryStorage(), { now: () => day0 });
    store.submitReview({ cardId: 'c-late', moduleId: 'm1', kind: 'cloze', rating: 3 }, day0); // +4d
    store.submitReview({ cardId: 'c-early', moduleId: 'm1', kind: 'cloze', rating: 2 }, day0); // +1d

    const day2 = new Date('2026-11-13T10:00:00.000Z');
    expect(store.getDueCards(day2).map((c) => c.id)).toEqual(['c-early']);

    const day5 = new Date('2026-11-16T10:00:00.000Z');
    expect(store.getDueCards(day5).map((c) => c.id)).toEqual(['c-early', 'c-late']);
  });

  it('computes continuous Memory Strength decay across Strong, Fading, and Due states', () => {
    const store = createRetentionStore(createMemoryStorage(), { now: () => day0 });
    store.submitReview({ cardId: 'c1', moduleId: 'm1', kind: 'cloze', rating: 3 }, day0); // 4d stability

    const fresh = store.getModuleSummaries(modules, day0)[0];
    expect(fresh.strength).toBe(100);
    expect(fresh.status).toBe('Strong');

    const day2 = new Date('2026-11-13T10:00:00.000Z');
    const fading = store.getModuleSummaries(modules, day2)[0];
    expect(fading.strength).toBe(71); // round(100 * exp(-ln(2) * 2 / 4))
    expect(fading.status).toBe('Fading');

    const day5 = new Date('2026-11-16T10:00:00.000Z');
    const due = store.getModuleSummaries(modules, day5)[0];
    expect(due.strength).toBeLessThan(50);
    expect(due.status).toBe('Due');
    expect(due.dueCount).toBe(1);
  });

  it('persists across reloaded store instances and tolerates corrupted JSON gracefully', () => {
    const storage = createMemoryStorage();
    const firstSession = createRetentionStore(storage, { now: () => day0 });
    firstSession.submitReview({ cardId: 'c1', moduleId: 'm1', kind: 'cloze', rating: 2 }, day0);

    const reloadedSession = createRetentionStore(storage, { now: () => day0 });
    expect(reloadedSession.getState().xp).toBe(15);
    expect(reloadedSession.getCard('c1')?.moduleId).toBe('m1');

    const corruptStore = createRetentionStore(
      createMemoryStorage({ 'de_sql_handbook_retention_v1': '{not-valid-json' }),
      { now: () => day0 },
    );
    expect(corruptStore.getState().xp).toBe(0);
    expect(corruptStore.getDueCards(day0)).toEqual([]);
  });

  it('tracks Consistency Streak, earns up to 2 Streak Freezes every 7 days, and absorbs missed days', () => {
    const store = createRetentionStore(createMemoryStorage(), { now: () => day0 });

    // Days 0..6 (7 consecutive days) -> earns 1 Streak Freeze; same-day repeats do not double-count
    for (let d = 0; d < 7; d += 1) {
      const ts = new Date(day0.getTime() + d * 86_400_000);
      store.submitReview({ cardId: 'c1', moduleId: 'm1', kind: 'cloze', rating: 3 }, ts);
      store.submitReview({ cardId: 'c1', moduleId: 'm1', kind: 'cloze', rating: 3 }, ts);
    }
    expect(store.getState().streakDays).toBe(7);
    expect(store.getState().freezesLeft).toBe(1);

    // Miss Day 7, return Day 8 (1 missed day <= 1 freeze) -> freeze absorbed, streak advances to 8
    const day8 = new Date(day0.getTime() + 8 * 86_400_000);
    store.submitReview({ cardId: 'c1', moduleId: 'm1', kind: 'cloze', rating: 3 }, day8);
    expect(store.getState().streakDays).toBe(8);
    expect(store.getState().freezesLeft).toBe(0);

    // Build streak through Day 14 -> earns Freeze; reach Day 21 -> second Freeze capped at max 2
    for (let d = 9; d <= 22; d += 1) {
      store.submitReview(
        { cardId: 'c1', moduleId: 'm1', kind: 'cloze', rating: 3 },
        new Date(day0.getTime() + d * 86_400_000),
      );
    }
    expect(store.getState().freezesLeft).toBe(2);

    // Exceeding freeze capacity resets streak to 1 and zeros freezes
    const afterLongGap = new Date(day0.getTime() + 30 * 86_400_000);
    store.submitReview({ cardId: 'c1', moduleId: 'm1', kind: 'cloze', rating: 3 }, afterLongGap);
    expect(store.getState().streakDays).toBe(1);
    expect(store.getState().freezesLeft).toBe(0);
  });

  it('seeds module stability from the 8-question diagnostic without dumping correct cards into Due Queue', () => {
    const store = createRetentionStore(createMemoryStorage(), { now: () => day0 });
    const summary = store.applyPlacementDiagnostic(
      [
        { cardId: 'diag-m1-a', moduleId: 'm1', correct: true },
        { cardId: 'diag-m1-b', moduleId: 'm1', correct: true },
        { cardId: 'diag-m2-a', moduleId: 'm2', correct: false },
        { cardId: 'diag-m2-b', moduleId: 'm2', correct: true },
        { cardId: 'diag-m3-a', moduleId: 'm3', correct: true },
        { cardId: 'diag-m4-a', moduleId: 'm4', correct: true },
        { cardId: 'diag-m5-a', moduleId: 'm5', correct: true },
        { cardId: 'diag-m6-a', moduleId: 'm6', correct: false },
      ],
      day0,
    );

    expect(summary.correctCount).toBe(6);
    expect(summary.totalCount).toBe(8);
    expect(store.getDueCards(day0).map((c) => c.id)).toEqual(['diag-m2-a', 'diag-m6-a']);
    const mod1 = store.getModuleSummaries(modules, day0)[0];
    expect(mod1.status).toBe('Strong');
    expect(mod1.dueCount).toBe(0);
  });

  it('exports and imports JSON round-trips cleanly and rejects invalid payloads without mutating state', () => {
    const storage = createMemoryStorage();
    const store = createRetentionStore(storage, { now: () => day0 });
    store.submitReview({ cardId: 'c1', moduleId: 'm1', kind: 'cloze', rating: 3 }, day0);

    const exported = store.exportStateJson();
    const invalidResult = store.importStateJson('{"version":999,"cards":"oops"}');
    expect(invalidResult.ok).toBe(false);
    expect(store.getState().xp).toBe(15);

    const targetStore = createRetentionStore(createMemoryStorage(), { now: () => day0 });
    const okResult = targetStore.importStateJson(exported);
    expect(okResult).toEqual({ ok: true, cardCount: 1 });
    expect(targetStore.getState().xp).toBe(15);
    expect(targetStore.getCard('c1')?.moduleId).toBe('m1');
  });

  it('restores clean slate across XP, streak, freezes, diagnostic status, storage key, and module summaries', () => {
    const storage = createMemoryStorage();
    const store = createRetentionStore(storage, { now: () => day0 });
    let notifyCount = 0;
    const unsub = store.subscribe(() => {
      notifyCount += 1;
    });

    store.applyPlacementDiagnostic(
      [{ cardId: 'diag-m1-a', moduleId: 'm1', correct: true }],
      day0,
    );
    expect(store.getState().xp).toBe(5);
    expect(store.getState().streakDays).toBe(1);
    expect(store.getModuleSummaries(modules, day0)[0].status).toBe('Strong');

    store.resetState();

    expect(store.getState()).toEqual({
      version: 1,
      xp: 0,
      streakDays: 0,
      freezesLeft: 0,
      lastActiveDate: null,
      diagnosticCompleted: false,
      cards: {},
    });
    expect(store.getModuleSummaries(modules, day0)[0]).toEqual({
      moduleId: 'm1',
      title: '01 · Foundations & NULLs',
      enrolledCount: 0,
      strength: 0,
      status: 'New',
      dueCount: 0,
    });
    expect(storage.getItem('de_sql_handbook_retention_v1')).toBeNull();
    expect(notifyCount).toBe(2);
    unsub();
  });
});
