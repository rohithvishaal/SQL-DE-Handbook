<script setup lang="ts">
import { onContentUpdated, useData, useRoute } from 'vitepress';
import { computed, nextTick, onMounted, onUnmounted, shallowRef, watch } from 'vue';
import { collectMiniMapSections, type MiniMapSection } from '../../handbook/sectionMiniMap';
import SectionMiniMap from './SectionMiniMap.vue';

const props = withDefaults(
  defineProps<{
    variant?: 'aside' | 'compact';
  }>(),
  {
    variant: 'aside',
  },
);

const { frontmatter } = useData();
const route = useRoute();
const sections = shallowRef<MiniMapSection[]>([]);

const isDisabled = computed(
  () =>
    frontmatter.value.layout === 'home' ||
    frontmatter.value.aside === false ||
    frontmatter.value.outline === false,
);

function refreshSections() {
  if (typeof document === 'undefined' || isDisabled.value) {
    sections.value = [];
    return;
  }
  const docRoot = document.querySelector('.VPDoc .vp-doc');
  sections.value = collectMiniMapSections(docRoot);
}

function onDocEnhanced() {
  void nextTick(refreshSections);
}

onContentUpdated(() => {
  void nextTick(refreshSections);
});

onMounted(() => {
  void nextTick(refreshSections);
  if (typeof window !== 'undefined') {
    window.addEventListener('de:doc-enhanced', onDocEnhanced);
  }
});

onUnmounted(() => {
  if (typeof window !== 'undefined') {
    window.removeEventListener('de:doc-enhanced', onDocEnhanced);
  }
});

watch(
  () => route.path,
  () => {
    void nextTick(refreshSections);
  },
);
</script>

<template>
  <ClientOnly>
    <SectionMiniMap :variant="props.variant" :sections="sections" :disabled="isDisabled" />
  </ClientOnly>
</template>
