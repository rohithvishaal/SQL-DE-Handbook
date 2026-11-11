<script setup lang="ts">
import { computed } from 'vue';
import { DIALECT_PLATFORMS, type NonDuckDbEngine } from '../../handbook/dialectGuard';
import type { RetentionStore } from '../../handbook/retentionStore';
import ClozeDrill from './ClozeDrill.vue';

const props = withDefaults(
  defineProps<{
    engine: NonDuckDbEngine;
    sql?: string;
    reason?: string;
    cardId?: string;
    moduleId?: string;
    clozePrompt?: string;
    clozePrefix?: string;
    clozeAnswer?: string;
    clozeSuffix?: string;
    store?: RetentionStore;
  }>(),
  {
    sql: '',
    reason: undefined,
    cardId: undefined,
    moduleId: 'm4',
    clozePrompt: undefined,
    clozePrefix: undefined,
    clozeAnswer: undefined,
    clozeSuffix: '',
    store: undefined,
  },
);

const platform = computed(() => DIALECT_PLATFORMS[props.engine]);
const effectiveReason = computed(() => props.reason ?? platform.value.reason);
const hasCloze = computed(
  () => Boolean(props.cardId && props.clozePrefix !== undefined && props.clozeAnswer),
);
</script>

<template>
  <section class="de-card de-dialect" :aria-label="`Dialect Block · ${platform.label}`">
    <div class="de-card-head">
      <div class="de-title-group">
        <span class="de-eyebrow">Dialect Block · {{ platform.label }}</span>
      </div>
      <span class="de-badge" data-status="dialect-locked">Non-Executable</span>
    </div>

    <div class="de-dialect-banner">
      <span>{{ effectiveReason }}</span>
      <span class="de-dialect-links">
        <a
          data-testid="dialect-platform-link"
          class="de-dialect-link"
          :href="platform.url"
          target="_blank"
          rel="noopener noreferrer"
        >
          {{ platform.ctaLabel }}
        </a>
        <a
          v-if="platform.altUrl && platform.altLabel"
          class="de-dialect-link"
          :href="platform.altUrl"
          target="_blank"
          rel="noopener noreferrer"
        >
          {{ platform.altLabel }}
        </a>
      </span>
    </div>

    <ClozeDrill
      v-if="hasCloze"
      :card-id="cardId!"
      :module-id="moduleId"
      kind="dialect"
      :embedded="true"
      :prompt="clozePrompt ?? `Recall ${platform.label} syntax:`"
      :prefix="clozePrefix!"
      :answer="clozeAnswer!"
      :suffix="clozeSuffix"
      :store="store"
    />

    <pre v-else class="de-code"><code>{{ sql }}</code></pre>
  </section>
</template>
