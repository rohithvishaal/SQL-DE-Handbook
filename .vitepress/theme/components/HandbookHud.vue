<script setup lang="ts">
import { computed } from 'vue';
import { useHandbookStore } from '../composables/useHandbookStore';
import { useModalController } from '../composables/useModalController';
import DueQueueDialog from './DueQueueDialog.vue';

const { store, revision } = useHandbookStore();
const { isOpen, activeTab, resetRequested, openModal, closeModal } = useModalController();

const summary = computed(() => {
  revision.value;
  const state = store.getState();
  const dueCount = store.getDueCards().length;
  return {
    dueCount,
    xp: state.xp,
    streakDays: state.streakDays,
    freezesLeft: state.freezesLeft,
  };
});
</script>

<template>
  <ClientOnly>
    <div class="de-hud" aria-label="Learning retention telemetry">
      <button
        type="button"
        class="de-hud-btn de-num"
        :data-has-due="String(summary.dueCount > 0)"
        title="Open Due Queue Review"
        @click="openModal('review')"
      >
        Due: {{ summary.dueCount }}
      </button>
      <button
        type="button"
        class="de-hud-btn de-num"
        title="Consistency Streak, XP & Backup"
        @click="openModal('telemetry')"
      >
        ◆ {{ summary.streakDays }}d · {{ summary.xp }} XP
      </button>
      <DueQueueDialog :open="isOpen" :initial-tab="activeTab" :prompt-reset="resetRequested" @close="closeModal" />
    </div>
  </ClientOnly>
</template>
