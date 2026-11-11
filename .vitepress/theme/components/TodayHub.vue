<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from 'vue';
import { PLACEMENT_QUESTIONS } from '../../handbook/catalog';
import { HANDBOOK_MODULES } from '../../handbook/modules';
import type { RetentionStore } from '../../handbook/retentionStore';
import { useHandbookStore } from '../composables/useHandbookStore';
import { useModalController } from '../composables/useModalController';
import { safeHref } from '../composables/useSafeHref';

const props = defineProps<{
  store?: RetentionStore;
}>();

const { store } = useHandbookStore(props.store);
const { openModal } = useModalController();

const rev = ref(0);
const unsubscribe = store.subscribe(() => {
  rev.value += 1;
});
onUnmounted(unsubscribe);

const diagnosticOpen = ref(false);
const selectedOptions = ref<Record<string, number>>({});
const diagnosticResult = ref<{ correctCount: number; totalCount: number; xpAwarded: number } | null>(null);

const state = computed(() => {
  rev.value;
  return store.getState();
});

const dueCards = computed(() => {
  rev.value;
  return store.getDueCards();
});

const moduleSummaries = computed(() => {
  rev.value;
  return store.getModuleSummaries(HANDBOOK_MODULES);
});

const allAnswered = computed(() => PLACEMENT_QUESTIONS.every((q) => selectedOptions.value[q.id] !== undefined));

watch(
  () => state.value.diagnosticCompleted,
  (completed) => {
    if (!completed) {
      diagnosticResult.value = null;
      selectedOptions.value = {};
    }
  },
);

function pickOption(qId: string, idx: number): void {
  selectedOptions.value = {
    ...selectedOptions.value,
    [qId]: idx,
  };
}

function submitDiagnostic(): void {
  const answers = PLACEMENT_QUESTIONS.map((q) => ({
    cardId: q.cardId,
    moduleId: q.moduleId,
    correct: selectedOptions.value[q.id] === q.correctIndex,
  }));
  diagnosticResult.value = store.applyPlacementDiagnostic(answers);
  diagnosticOpen.value = false;
}
</script>

<template>
  <div class="de-zen-hub">
    <header class="de-zen-hero">
      <div class="de-zen-title-row">
        <div>
          <span class="de-eyebrow">Command-First Zen · Today Hub</span>
          <h1 style="margin: 0.2rem 0 0;">Data Engineering SQL Practice</h1>
        </div>
        <div class="de-kpi-strip">
          <button
            type="button"
            class="de-btn"
            :class="dueCards.length > 0 ? 'de-btn-primary' : 'de-btn-subtle'"
            @click="openModal('review')"
          >
            <span>Due: <span class="de-num">{{ dueCards.length }}</span></span>
          </button>
          <button type="button" class="de-btn de-btn-subtle de-num" @click="openModal('telemetry')">
            ◆ {{ state.streakDays }}d · {{ state.xp }} XP · {{ state.freezesLeft }}/2 Freezes
          </button>
          <button type="button" class="de-btn de-btn-subtle" popovertarget="de-zen-module-popover">
            Modules ▾
          </button>
        </div>
      </div>

      <nav id="de-zen-module-popover" class="de-popover" popover aria-label="Quick Handbook Module jump">
        <strong style="display: block; margin-block-end: 0.45rem; font-size: 0.85rem;">Jump to Handbook Module</strong>
        <div class="de-popover-list">
          <a v-for="mod in HANDBOOK_MODULES" :key="mod.moduleId" class="de-popover-link" :href="safeHref(mod.link)">
            {{ mod.title }}
          </a>
        </div>
      </nav>
    </header>

    <section class="de-card" aria-labelledby="placement-heading">
      <div class="de-card-head">
        <div>
          <span class="de-eyebrow">Cold-Start Calibration</span>
          <h2 id="placement-heading" style="margin: 0.15rem 0 0; font-size: 1.05rem;">Optional 8-Question Placement Check</h2>
        </div>
        <button
          v-if="!diagnosticOpen"
          type="button"
          class="de-btn de-btn-primary"
          data-testid="start-diagnostic-btn"
          @click="diagnosticOpen = true"
        >
          {{ state.diagnosticCompleted ? 'Retake Placement Check' : 'Start 2-Min Check' }}
        </button>
      </div>

      <p v-if="diagnosticResult" class="de-feedback-text" style="margin-block-start: 0.65rem;">
        ✓ Calibration complete: {{ diagnosticResult.correctCount }}/{{ diagnosticResult.totalCount }} Strong seeded (+{{ diagnosticResult.xpAwarded }} XP).
      </p>

      <div v-if="diagnosticOpen" class="de-diagnostic-list">
        <fieldset
          v-for="(q, idx) in PLACEMENT_QUESTIONS"
          :key="q.id"
          class="de-diagnostic-item"
          data-testid="diagnostic-question"
        >
          <legend class="de-prompt">{{ idx + 1 }}. {{ q.prompt }}</legend>
          <div class="de-option-grid">
            <button
              v-for="(opt, optIdx) in q.options"
              :key="optIdx"
              type="button"
              :data-testid="`diag-q-${idx}-opt-${optIdx}`"
              :class="['de-btn', selectedOptions[q.id] === optIdx ? 'de-btn-primary' : 'de-btn-subtle']"
              @click="pickOption(q.id, optIdx)"
            >
              {{ opt }}
            </button>
          </div>
        </fieldset>

        <div class="de-feedback-row">
          <button type="button" class="de-btn de-btn-subtle" @click="diagnosticOpen = false">Cancel</button>
          <button
            type="button"
            class="de-btn de-btn-primary"
            data-testid="submit-diagnostic-btn"
            :disabled="!allAnswered"
            @click="submitDiagnostic"
          >
            Seed Module Memory Strength
          </button>
        </div>
      </div>
    </section>

    <section class="de-card" aria-labelledby="modules-strength-heading">
      <div class="de-card-head" style="margin-block-end: 0.75rem;">
        <h2 id="modules-strength-heading" style="margin: 0; font-size: 1.05rem;">Handbook Modules · Memory Strength</h2>
        <button
          type="button"
          class="de-btn de-btn-subtle"
          data-testid="hub-reset-btn"
          @click="openModal('telemetry', { promptReset: true })"
        >
          Reset Progress…
        </button>
      </div>
      <div class="de-module-grid">
        <a
          v-for="mod in moduleSummaries"
          :key="mod.moduleId"
          class="de-module-tile"
          :href="safeHref(HANDBOOK_MODULES.find((m) => m.moduleId === mod.moduleId)?.link ?? '/')"
        >
          <div class="de-rail-link">
            <strong>{{ mod.title }}</strong>
            <span class="de-badge" :data-status="mod.status.toLowerCase()">
              {{ mod.enrolledCount > 0 ? `${mod.strength}% ${mod.status}` : 'New' }}
            </span>
          </div>
          <div class="de-meter-track" aria-hidden="true">
            <div
              class="de-meter-fill"
              :data-status="mod.status.toLowerCase()"
              :style="{ inlineSize: `${mod.enrolledCount > 0 ? mod.strength : 0}%` }"
            />
          </div>
        </a>
      </div>
    </section>
  </div>
</template>
