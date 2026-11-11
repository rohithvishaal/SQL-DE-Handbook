<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { formatIntervalDays, REVIEW_RATING_OPTIONS } from '../../handbook/catalog';
import type { CardKind, RetentionStore, ReviewRating } from '../../handbook/retentionStore';
import { useHandbookStore } from '../composables/useHandbookStore';

const props = withDefaults(
  defineProps<{
    cardId: string;
    moduleId: string;
    prompt: string;
    prefix: string;
    answer: string;
    suffix?: string;
    baseXp?: number;
    kind?: CardKind;
    embedded?: boolean;
    placeholder?: string;
    store?: RetentionStore;
  }>(),
  {
    suffix: '',
    baseXp: 15,
    kind: 'cloze',
    embedded: false,
    placeholder: 'click or press Enter to reveal SQL',
    store: undefined,
  },
);

const { store } = useHandbookStore(props.store);

const rev = ref(0);
const unsubscribe = store.subscribe(() => {
  rev.value += 1;
});
onUnmounted(unsubscribe);

const revealed = ref(false);
const hydrated = ref(Boolean(props.store));
const lastFeedback = ref<{ xpAwarded: number; nextLabel: string } | null>(null);

onMounted(() => {
  hydrated.value = true;
});

watch(
  () => props.cardId,
  () => {
    revealed.value = false;
    lastFeedback.value = null;
  },
);

const savedCard = computed(() => {
  rev.value;
  if (!hydrated.value) return undefined;
  return store.getCard(props.cardId);
});

watch(savedCard, (next, prev) => {
  if (prev && !next) {
    revealed.value = false;
    lastFeedback.value = null;
  }
});

const statusLabel = computed(() => {
  if (!savedCard.value) return 'New';
  const dueMs = Date.parse(savedCard.value.nextDueAt);
  if (dueMs <= Date.now()) return 'Due';
  return 'Scheduled';
});

const ratings = REVIEW_RATING_OPTIONS;

function toggleReveal(): void {
  revealed.value = !revealed.value;
}

function rateCard(rating: ReviewRating): void {
  const result = store.submitReview({
    cardId: props.cardId,
    moduleId: props.moduleId,
    kind: props.kind,
    rating,
    baseXp: props.baseXp,
  });
  revealed.value = false;
  lastFeedback.value = {
    xpAwarded: result.xpAwarded,
    nextLabel: formatIntervalDays(result.intervalDays),
  };
}

function practiceAgain(): void {
  lastFeedback.value = null;
  revealed.value = false;
}

function onCardKeydown(event: KeyboardEvent): void {
  if (!revealed.value) return;
  if (event.key === '1' || event.key === '2' || event.key === '3' || event.key === '4') {
    event.preventDefault();
    rateCard(Number(event.key) as ReviewRating);
  }
}
</script>

<template>
  <section
    :class="[props.embedded ? 'de-cloze-embedded' : 'de-card', 'de-cloze']"
    data-testid="cloze-card"
    :aria-label="`Cloze Drill: ${prompt}`"
    @keydown="onCardKeydown"
  >
    <div v-if="!props.embedded" class="de-card-head">
      <div class="de-title-group">
        <span class="de-eyebrow">Active Recall · Cloze Drill</span>
        <p class="de-prompt">{{ prompt }}</p>
      </div>
      <span class="de-badge" :data-status="statusLabel.toLowerCase()">
        {{ statusLabel }}
      </span>
    </div>
    <p v-else class="de-prompt" style="margin-block-start: 0.65rem;">{{ prompt }}</p>

    <pre class="de-code"><code>{{ prefix }}<button
      type="button"
      class="de-cloze-blank"
      data-testid="cloze-reveal-btn"
      :aria-expanded="String(revealed)"
      @click="toggleReveal"
    >{{ revealed ? answer : `[ ${placeholder} ]` }}</button>{{ suffix }}</code></pre>

    <div v-if="revealed" class="de-rating-row" data-testid="cloze-ratings" role="group" aria-label="Rate recall confidence">
      <button
        v-for="item in ratings"
        :key="item.rating"
        type="button"
        :data-testid="`cloze-rate-${item.rating}`"
        :class="['de-btn', item.rating === 3 ? 'de-btn-primary' : 'de-btn-subtle']"
        @click="rateCard(item.rating)"
      >
        <span><kbd>{{ item.rating }}</kbd> {{ item.label }}</span>
        <span class="de-num">{{ item.hint }}</span>
      </button>
    </div>

    <div v-else-if="lastFeedback" class="de-feedback-row">
      <span class="de-feedback-text">
        ✓ Recorded · Next review in {{ lastFeedback.nextLabel }} (+{{ lastFeedback.xpAwarded }} XP)
      </span>
      <button
        type="button"
        class="de-btn de-btn-subtle"
        data-testid="cloze-practice-again"
        @click="practiceAgain"
      >
        Practice again
      </button>
    </div>
  </section>
</template>
