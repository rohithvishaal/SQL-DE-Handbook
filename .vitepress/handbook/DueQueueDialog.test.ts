import { describe, expect, it } from 'vitest';
import { mount } from '@vue/test-utils';
import TodayHub from '../theme/components/TodayHub.vue';
import DueQueueDialog from '../theme/components/DueQueueDialog.vue';
import { createMemoryFallbackStorage, createRetentionStore } from './retentionStore';

describe('Zen Today Hub & Due Queue Modal (Seam #3 Ticket 02)', () => {
  const now = new Date('2026-11-11T10:00:00.000Z');

  it('starts Today Hub empty and allows running the 8-question Placement Check', async () => {
    const store = createRetentionStore(createMemoryFallbackStorage(), { now: () => now });
    const wrapper = mount(TodayHub, { props: { store } });

    expect(wrapper.text()).toContain('Today Hub');
    expect(wrapper.text()).toContain('Due: 0');
    expect(wrapper.text()).toContain('Placement Check');

    await wrapper.get('[data-testid="start-diagnostic-btn"]').trigger('click');
    const questions = wrapper.findAll('[data-testid="diagnostic-question"]');
    expect(questions).toHaveLength(8);

    // Choose option 0 cleanly on all questions via radio/button clicks then apply
    for (let i = 0; i < 8; i += 1) {
      await wrapper.get(`[data-testid="diag-q-${i}-opt-0"]`).trigger('click');
    }
    await wrapper.get('[data-testid="submit-diagnostic-btn"]').trigger('click');

    expect(Object.keys(store.getState().cards).length).toBe(8);
  });

  it('supports Space to reveal and 1-4 rating inside Due Queue dialog to advance queue', async () => {
    const store = createRetentionStore(createMemoryFallbackStorage(), { now: () => now });
    store.submitReview({ cardId: 'm1-having-aggregate-repeat', moduleId: 'm1', kind: 'cloze', rating: 1 }, now);
    const later = new Date('2026-11-11T10:20:00.000Z');

    const storeAtDue = createRetentionStore(
      {
        getItem: () => JSON.stringify(store.getState()),
        setItem: () => {},
        removeItem: () => {},
      },
      { now: () => later },
    );

    const wrapper = mount(DueQueueDialog, {
      props: { open: true, store: storeAtDue },
    });

    const dlg = wrapper.get('dialog');
    expect(dlg.attributes('closedby')).toBe('any');
    expect(wrapper.text()).toContain('SELECT source_system');

    await dlg.trigger('keydown', { key: ' ' });
    expect(wrapper.text()).toContain('HAVING AVG(row_count) < 10000');

    await dlg.trigger('keydown', { key: '3' });
    expect(storeAtDue.getDueCards(later)).toHaveLength(0);
    expect(wrapper.text()).toContain('All Due Queue cards reviewed');
  });

  it('requires explicit Clean Slate confirmation before resetting XP, streak, and module memory strength', async () => {
    const store = createRetentionStore(createMemoryStorageWithProgress(), { now: () => now });
    expect(store.getState().xp).toBe(15);

    const wrapper = mount(DueQueueDialog, {
      props: { open: true, initialTab: 'telemetry', store },
      attachTo: document.body,
    });

    const startBtn = wrapper.get('[data-testid="clean-slate-start-btn"]');
    const confirmBtn = wrapper.get('[data-testid="clean-slate-confirm-btn"]');
    expect((confirmBtn.element as HTMLButtonElement).disabled).toBe(true);

    // Step 1: Enter confirmation mode without mutating state yet; focus moves to safe Keep Progress button
    await startBtn.trigger('click');
    const keepBtn = wrapper.get('[data-testid="clean-slate-cancel-btn"]');
    expect(document.activeElement).toBe(keepBtn.element);
    expect((confirmBtn.element as HTMLButtonElement).disabled).toBe(false);
    expect(store.getState().xp).toBe(15);

    // Cancel keeps progress untouched
    await keepBtn.trigger('click');
    expect(store.getState().xp).toBe(15);

    // Confirm resets XP, streak, and memory strength completely
    await wrapper.get('[data-testid="clean-slate-start-btn"]').trigger('click');
    await wrapper.get('[data-testid="clean-slate-confirm-btn"]').trigger('click');

    expect(store.getState().xp).toBe(0);
    expect(store.getState().streakDays).toBe(0);
    expect(Object.keys(store.getState().cards)).toHaveLength(0);
    expect(wrapper.text()).toContain('0 XP');
    expect(wrapper.text()).toContain('Clean slate restored');
    wrapper.unmount();
  });
});

function createMemoryStorageWithProgress() {
  const s = createMemoryFallbackStorage();
  const seeded = createRetentionStore(s, { now: () => new Date('2026-11-11T10:00:00.000Z') });
  seeded.submitReview({ cardId: 'm1-having-aggregate-repeat', moduleId: 'm1', kind: 'cloze', rating: 3 });
  return s;
}
