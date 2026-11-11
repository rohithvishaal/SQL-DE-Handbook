<script setup lang="ts">
import { computed } from 'vue';
import { HANDBOOK_MODULES } from '../../handbook/modules';
import { useHandbookStore } from '../composables/useHandbookStore';
import { useModalController } from '../composables/useModalController';
import { safeHref } from '../composables/useSafeHref';

const { store, revision } = useHandbookStore();
const { openModal } = useModalController();

const linksByModuleId = new Map(HANDBOOK_MODULES.map((m) => [m.moduleId, m.link]));

const moduleSummaries = computed(() => {
  revision.value;
  return store.getModuleSummaries(HANDBOOK_MODULES).map((summary) => ({
    ...summary,
    link: linksByModuleId.get(summary.moduleId) ?? '/',
  }));
});
</script>

<template>
  <ClientOnly>
    <section class="de-rail" aria-label="Module Memory Strength">
      <div class="de-rail-head">
        <span>Memory <span class="de-num">%</span></span>
        <button
          type="button"
          class="de-rail-reset"
          data-testid="rail-reset-btn"
          aria-label="Reset memory strength and XP"
          @click="openModal('telemetry', { promptReset: true })"
        >
          Reset
        </button>
      </div>
      <ul class="de-rail-list">
        <li v-for="mod in moduleSummaries" :key="mod.moduleId">
          <a class="de-rail-link" :href="safeHref(mod.link)">
            <span>{{ mod.title }}</span>
            <span class="de-num">{{ mod.enrolledCount > 0 ? `${mod.strength}%` : mod.status }}</span>
          </a>
          <div class="de-meter-track" aria-hidden="true">
            <div
              class="de-meter-fill"
              :data-status="mod.status.toLowerCase()"
              :style="{ inlineSize: `${mod.enrolledCount > 0 ? mod.strength : 0}%` }"
            />
          </div>
        </li>
      </ul>
    </section>
  </ClientOnly>
</template>
