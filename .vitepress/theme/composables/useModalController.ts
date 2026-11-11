import { ref } from 'vue';

export type HandbookModalTab = 'review' | 'telemetry';

export interface OpenModalOptions {
  promptReset?: boolean;
}

const isOpen = ref(false);
const activeTab = ref<HandbookModalTab>('review');
const resetRequested = ref(false);

export function useModalController() {
  function openModal(tab: HandbookModalTab = 'review', options: OpenModalOptions = {}): void {
    activeTab.value = tab;
    resetRequested.value = Boolean(options.promptReset);
    isOpen.value = true;
  }

  function closeModal(): void {
    isOpen.value = false;
    resetRequested.value = false;
  }

  return {
    isOpen,
    activeTab,
    resetRequested,
    openModal,
    closeModal,
  };
}
