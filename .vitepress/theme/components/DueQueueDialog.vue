<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { CARD_CATALOG, REVIEW_RATING_OPTIONS } from '../../handbook/catalog';
import { HANDBOOK_MODULES } from '../../handbook/modules';
import type { RetentionStore, ReviewRating } from '../../handbook/retentionStore';
import { useHandbookStore } from '../composables/useHandbookStore';
import type { HandbookModalTab } from '../composables/useModalController';

const props = withDefaults(
  defineProps<{
    open: boolean;
    initialTab?: HandbookModalTab;
    promptReset?: boolean;
    store?: RetentionStore;
  }>(),
  {
    initialTab: 'review',
    promptReset: false,
    store: undefined,
  },
);

const emit = defineEmits<{
  (e: 'close'): void;
}>();

const { store } = useHandbookStore(props.store);
const dialogEl = ref<HTMLDialogElement | null>(null);
const rev = ref(0);
const unsubscribe = store.subscribe(() => {
  rev.value += 1;
});
onUnmounted(unsubscribe);

const activeTab = ref<HandbookModalTab>(props.initialTab);
const revealed = ref(false);
const jsonInput = ref('');
const backupFeedback = ref<{ ok: boolean; text: string } | null>(null);
const confirmingReset = ref(false);
const startResetBtn = ref<HTMLButtonElement | null>(null);
const cancelResetBtn = ref<HTMLButtonElement | null>(null);

watch(
  () => props.initialTab,
  (next) => {
    activeTab.value = next;
  },
);

watch(
  () => props.promptReset,
  (shouldPrompt) => {
    if (shouldPrompt && props.open) {
      activeTab.value = 'telemetry';
      confirmingReset.value = true;
      void nextTick(() => {
        cancelResetBtn.value?.focus();
      });
    }
  },
);

function syncDialogOpen(shouldOpen: boolean): void {
  const dlg = dialogEl.value;
  if (!dlg) return;
  if (shouldOpen) {
    revealed.value = false;
    backupFeedback.value = null;
    confirmingReset.value = Boolean(props.promptReset);
    if (!dlg.open) {
      if (typeof dlg.showModal === 'function') {
        try {
          dlg.showModal();
        } catch {
          dlg.setAttribute('open', '');
        }
      } else {
        dlg.setAttribute('open', '');
      }
    }
    if (props.promptReset) {
      activeTab.value = 'telemetry';
      void nextTick(() => {
        cancelResetBtn.value?.focus();
      });
    }
  } else if (dlg.open) {
    confirmingReset.value = false;
    if (typeof dlg.close === 'function') dlg.close();
    else dlg.removeAttribute('open');
  }
}

watch(
  () => props.open,
  (val) => syncDialogOpen(val),
  { flush: 'post' },
);

let pointerDownOutside = false;
function isOutsideDialog(event: PointerEvent, dlg: HTMLDialogElement): boolean {
  const rect = dlg.getBoundingClientRect();
  return (
    event.clientX < rect.left ||
    event.clientX > rect.right ||
    event.clientY < rect.top ||
    event.clientY > rect.bottom
  );
}

onMounted(() => {
  syncDialogOpen(props.open);
  const dlg = dialogEl.value;
  if (!dlg || 'closedBy' in HTMLDialogElement.prototype) return;

  const onDown = (e: PointerEvent) => {
    pointerDownOutside = isOutsideDialog(e, dlg);
  };
  const onUp = (e: PointerEvent) => {
    if (pointerDownOutside && isOutsideDialog(e, dlg)) {
      if (typeof dlg.close === 'function') dlg.close();
      else {
        dlg.removeAttribute('open');
        emit('close');
      }
    }
    pointerDownOutside = false;
  };
  dlg.addEventListener('pointerdown', onDown);
  dlg.addEventListener('pointerup', onUp);
  onUnmounted(() => {
    dlg.removeEventListener('pointerdown', onDown);
    dlg.removeEventListener('pointerup', onUp);
  });
});

const dueCards = computed(() => {
  rev.value;
  return store.getDueCards();
});

const currentCard = computed(() => {
  const first = dueCards.value[0];
  if (!first) return null;
  const meta = CARD_CATALOG[first.id];
  return {
    card: first,
    prompt: meta?.prompt ?? `Review ${first.kind} item: ${first.id}`,
    answer: meta?.answer ?? 'Check handbook module reference solution.',
  };
});

const stateSnapshot = computed(() => {
  rev.value;
  return store.getState();
});

const moduleSummaries = computed(() => {
  rev.value;
  return store.getModuleSummaries(HANDBOOK_MODULES);
});

const ratingOptions = REVIEW_RATING_OPTIONS;
const reviewTabEl = ref<HTMLButtonElement | null>(null);
const telemetryTabEl = ref<HTMLButtonElement | null>(null);

function onTabKeydown(event: KeyboardEvent): void {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
  event.preventDefault();
  if (event.key === 'Home') activeTab.value = 'review';
  else if (event.key === 'End') activeTab.value = 'telemetry';
  else activeTab.value = activeTab.value === 'review' ? 'telemetry' : 'review';
  void nextTick(() => {
    (activeTab.value === 'review' ? reviewTabEl.value : telemetryTabEl.value)?.focus();
  });
}

function handleDialogClose(): void {
  if (dialogEl.value) dialogEl.value.returnValue = '';
  revealed.value = false;
  confirmingReset.value = false;
  emit('close');
}

function enterResetConfirmation(): void {
  confirmingReset.value = true;
  void nextTick(() => {
    cancelResetBtn.value?.focus();
  });
}

function cancelResetConfirmation(): void {
  confirmingReset.value = false;
  void nextTick(() => {
    startResetBtn.value?.focus();
  });
}

function confirmCleanSlateReset(): void {
  store.resetState();
  jsonInput.value = '';
  confirmingReset.value = false;
  backupFeedback.value = {
    ok: true,
    text: 'Clean slate restored — XP, streak, and module memory strength reset to 0.',
  };
  void nextTick(() => {
    startResetBtn.value?.focus();
  });
}

function submitModalRating(rating: ReviewRating): void {
  if (!currentCard.value) return;
  const c = currentCard.value.card;
  store.submitReview({
    cardId: c.id,
    moduleId: c.moduleId,
    kind: c.kind,
    rating,
  });
  revealed.value = false;
}

function onDialogKeydown(event: KeyboardEvent): void {
  const target = event.target as HTMLElement | null;
  const tag = target?.tagName;
  const inInput = tag === 'INPUT' || tag === 'TEXTAREA' || Boolean(target?.isContentEditable);
  if (inInput || activeTab.value !== 'review' || !currentCard.value) return;

  if (event.key === ' ' && !revealed.value) {
    event.preventDefault();
    revealed.value = true;
    return;
  }
  if (revealed.value && ['1', '2', '3', '4'].includes(event.key)) {
    event.preventDefault();
    submitModalRating(Number(event.key) as ReviewRating);
  }
}

function downloadBackup(): void {
  const json = store.exportStateJson();
  jsonInput.value = json;
  if (typeof URL.createObjectURL === 'function') {
    const blob = new Blob([json], { type: 'application/json' });
    const href = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = href;
    a.download = `de-sql-handbook-backup-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(href);
  }
  backupFeedback.value = { ok: true, text: 'Exported JSON snapshot cleanly.' };
}

function applyImportedJson(): void {
  const res = store.importStateJson(jsonInput.value);
  backupFeedback.value = res.ok
    ? { ok: true, text: `Imported ${res.cardCount} Recall Card(s).` }
    : { ok: false, text: res.error };
}

async function onFileSelected(event: Event): Promise<void> {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;
  jsonInput.value = await file.text();
  applyImportedJson();
  input.value = '';
}
</script>

<template>
  <dialog
    ref="dialogEl"
    class="de-dialog"
    closedby="any"
    aria-labelledby="de-modal-title"
    @close="handleDialogClose"
    @keydown="onDialogKeydown"
  >
    <div class="de-dialog-head">
      <div>
        <h2 id="de-modal-title" class="de-dialog-title">
          {{ activeTab === 'review' ? `Due Queue (${dueCards.length})` : 'Retention Telemetry & Backup' }}
        </h2>
        <div class="de-dialog-tabs" role="tablist" aria-label="Dialog mode" @keydown="onTabKeydown">
          <button
            ref="reviewTabEl"
            type="button"
            role="tab"
            class="de-btn de-btn-subtle"
            :tabindex="activeTab === 'review' ? 0 : -1"
            :aria-selected="activeTab === 'review'"
            @click="activeTab = 'review'; confirmingReset = false"
          >
            Due Queue ({{ dueCards.length }})
          </button>
          <button
            ref="telemetryTabEl"
            type="button"
            role="tab"
            class="de-btn de-btn-subtle"
            :tabindex="activeTab === 'telemetry' ? 0 : -1"
            :aria-selected="activeTab === 'telemetry'"
            @click="activeTab = 'telemetry'"
          >
            Streak &amp; Backup
          </button>
        </div>
      </div>
      <form method="dialog">
        <button type="submit" value="close" class="de-btn de-btn-subtle">Close (<kbd>Esc</kbd>)</button>
      </form>
    </div>

    <div v-if="activeTab === 'review'" class="de-dialog-body">
      <template v-if="currentCard">
        <p class="de-eyebrow">{{ currentCard.card.moduleId.toUpperCase() }} · {{ currentCard.card.kind }}</p>
        <p class="de-prompt" style="margin-block-end: 0.75rem;">{{ currentCard.prompt }}</p>

        <div v-if="!revealed">
          <button
            type="button"
            class="de-btn de-btn-primary"
            data-testid="due-reveal-btn"
            @click="revealed = true"
          >
            Show Answer (<kbd>Space</kbd>)
          </button>
        </div>

        <template v-else>
          <pre class="de-code"><code>{{ currentCard.answer }}</code></pre>
          <div class="de-rating-row" role="group" aria-label="Rate Due Card">
            <button
              v-for="item in ratingOptions"
              :key="item.rating"
              type="button"
              :class="['de-btn', item.rating === 3 ? 'de-btn-primary' : 'de-btn-subtle']"
              @click="submitModalRating(item.rating)"
            >
              <span><kbd>{{ item.rating }}</kbd> {{ item.label }}</span>
              <span class="de-num">{{ item.hint }}</span>
            </button>
          </div>
        </template>
      </template>

      <div v-else class="de-empty-queue">
        <span class="de-badge" data-status="scheduled">✓ All Due Queue cards reviewed for today.</span>
      </div>
    </div>

    <div v-else class="de-dialog-body">
      <div class="de-kpi-strip">
        <span class="de-badge" data-status="scheduled">◆ {{ stateSnapshot.streakDays }}-Day Streak</span>
        <span class="de-badge">{{ stateSnapshot.freezesLeft }}/2 Streak Freezes</span>
        <span class="de-badge de-num">{{ stateSnapshot.xp }} XP</span>
      </div>

      <ul class="de-rail-list" style="margin-block: 1rem;">
        <li v-for="mod in moduleSummaries" :key="mod.moduleId">
          <div class="de-rail-link">
            <span>{{ mod.title }}</span>
            <span class="de-num">{{ mod.enrolledCount > 0 ? `${mod.strength}% · ${mod.status}` : 'New' }}</span>
          </div>
          <div class="de-meter-track" aria-hidden="true">
            <div
              class="de-meter-fill"
              :data-status="mod.status.toLowerCase()"
              :style="{ inlineSize: `${mod.enrolledCount > 0 ? mod.strength : 0}%` }"
            />
          </div>
        </li>
      </ul>

      <div class="de-backup-box">
        <div class="de-backup-actions">
          <button type="button" class="de-btn de-btn-primary" @click="downloadBackup">Export JSON</button>
          <label class="de-btn de-btn-subtle">
            Import File
            <input type="file" accept="application/json" style="display: none;" @change="onFileSelected" />
          </label>
          <button type="button" class="de-btn de-btn-subtle" @click="applyImportedJson">Apply Pasted JSON</button>
        </div>
        <textarea
          v-model="jsonInput"
          rows="4"
          class="de-json-area de-num"
          aria-label="Backup JSON payload"
          placeholder="Paste exported JSON snapshot here to restore progress across devices..."
        />
        <p v-if="backupFeedback" role="status" class="de-feedback-text" :data-error="String(!backupFeedback.ok)">
          {{ backupFeedback.text }}
        </p>
      </div>

      <div class="de-danger-zone">
        <div>
          <strong>Clean Slate</strong>
          <p class="de-danger-desc">
            Reset XP, consistency streak, streak freezes, placement calibration, and all module memory strength back to zero.
          </p>
        </div>
        <p
          id="de-reset-warning"
          class="de-reset-warning"
          role="note"
          :style="{ visibility: confirmingReset ? 'visible' : 'hidden' }"
        >
          Confirm clean slate? Export a JSON backup first if you want a snapshot; otherwise all local progress clears immediately.
        </p>
        <div class="de-reset-actions">
          <button
            type="button"
            class="de-btn de-btn-danger"
            data-testid="clean-slate-confirm-btn"
            :disabled="!confirmingReset"
            :style="{ visibility: confirmingReset ? 'visible' : 'hidden' }"
            @click="confirmCleanSlateReset"
          >
            Confirm Clean Slate
          </button>
          <button
            v-if="!confirmingReset"
            ref="startResetBtn"
            type="button"
            class="de-btn de-btn-subtle"
            data-testid="clean-slate-start-btn"
            @click="enterResetConfirmation"
          >
            Reset Progress…
          </button>
          <button
            v-else
            ref="cancelResetBtn"
            type="button"
            class="de-btn de-btn-subtle"
            data-testid="clean-slate-cancel-btn"
            aria-describedby="de-reset-warning"
            @click="cancelResetConfirmation"
          >
            Keep Progress
          </button>
        </div>
      </div>
    </div>
  </dialog>
</template>
