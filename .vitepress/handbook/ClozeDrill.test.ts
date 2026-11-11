import { describe, expect, it } from 'vitest';
import { mount } from '@vue/test-utils';
import ClozeDrill from '../theme/components/ClozeDrill.vue';
import { createRetentionStore, type StorageLike } from './retentionStore';

function createMemoryStorage(): StorageLike {
  const map = new Map<string, string>();
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

describe('ClozeDrill component (Seam #3 Ticket 01 smoke)', () => {
  const now = new Date('2026-11-11T10:00:00.000Z');

  it('masks SQL answer until revealed and exposes Review Ratings 1-4', async () => {
    const store = createRetentionStore(createMemoryStorage(), { now: () => now });
    const wrapper = mount(ClozeDrill, {
      props: {
        cardId: 'm1-having',
        moduleId: 'm1',
        prompt: 'Filter groups after aggregation:',
        prefix: 'SELECT user_id, COUNT(*) FROM raw_events GROUP BY user_id ',
        answer: 'HAVING COUNT(*) > 1',
        suffix: ';',
        store,
      },
    });

    const toggleBtn = wrapper.get('[data-testid="cloze-reveal-btn"]');
    expect(toggleBtn.attributes('aria-expanded')).toBe('false');
    expect(wrapper.text()).not.toContain('HAVING COUNT(*) > 1');
    expect(wrapper.find('[data-testid="cloze-ratings"]').exists()).toBe(false);

    await toggleBtn.trigger('click');

    expect(wrapper.get('[data-testid="cloze-reveal-btn"]').attributes('aria-expanded')).toBe('true');
    expect(wrapper.text()).toContain('HAVING COUNT(*) > 1');
    expect(wrapper.findAll('[data-testid="cloze-ratings"] button')).toHaveLength(4);
  });

  it('records Review Rating in the retention store via click or keyboard 1-4 and persists across remount', async () => {
    const storage = createMemoryStorage();
    const storeA = createRetentionStore(storage, { now: () => now });
    const wrapperA = mount(ClozeDrill, {
      props: {
        cardId: 'm1-having',
        moduleId: 'm1',
        prompt: 'Filter groups after aggregation:',
        prefix: 'SELECT user_id, COUNT(*) FROM raw_events GROUP BY user_id ',
        answer: 'HAVING COUNT(*) > 1',
        suffix: ';',
        store: storeA,
      },
    });

    await wrapperA.get('[data-testid="cloze-reveal-btn"]').trigger('click');
    await wrapperA.get('[data-testid="cloze-rate-3"]').trigger('click');

    expect(storeA.getState().xp).toBe(15);
    expect(storeA.getCard('m1-having')?.nextDueAt).toBe('2026-11-15T10:00:00.000Z');
    expect(wrapperA.text()).toContain('+15 XP');

    // Keyboard shortcut '4' (Easy) works when revealed inside the ClozeDrill element
    await wrapperA.get('[data-testid="cloze-practice-again"]').trigger('click');
    await wrapperA.get('[data-testid="cloze-reveal-btn"]').trigger('click');
    await wrapperA.get('[data-testid="cloze-card"]').trigger('keydown', { key: '4' });
    expect(storeA.getState().xp).toBe(30);

    // Reloaded store reflects persisted review
    const storeB = createRetentionStore(storage, { now: () => now });
    expect(storeB.getState().xp).toBe(30);
    expect(storeB.getCard('m1-having')?.reps).toBe(2);
  });
});
