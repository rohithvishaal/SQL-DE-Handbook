<script setup lang="ts">
import { onContentUpdated, useRoute } from 'vitepress';
import { nextTick, onMounted, onUnmounted, watch } from 'vue';
import { enhanceCheatsheetSections, revealAccordionTarget } from '../../handbook/cheatsheetAccordion';
import { getQuizSolutionsForRoute } from '../../handbook/quizCatalog';
import { enhanceQuizDocument } from '../../handbook/quizEnhancer';

const route = useRoute();

function isCheatsheetRoute(path: string): boolean {
  const normalized = path.replace(/\.html$/i, '');
  return normalized.startsWith('/cheatsheets/') && normalized !== '/cheatsheets/';
}

function revealCurrentHashTarget(): void {
  if (typeof window === 'undefined' || window.location.hash.length <= 1) return;
  const rawId = decodeURIComponent(window.location.hash.slice(1));
  if (!rawId) return;
  const target = document.getElementById(rawId);
  if (target) {
    revealAccordionTarget(target);
    void nextTick(() => {
      target.scrollIntoView?.({ block: 'start' });
    });
  }
}

function applyEnhancements(): void {
  if (typeof document === 'undefined') return;
  const docRoot = document.querySelector<HTMLElement>('.VPDoc .vp-doc');
  if (!docRoot) return;

  const quizSolutions = getQuizSolutionsForRoute(route.path);
  if (quizSolutions) {
    if (!docRoot.querySelector('.de-quiz-card')) {
      delete docRoot.dataset.deQuizEnhanced;
    }
    enhanceQuizDocument(docRoot, quizSolutions);
    window.dispatchEvent(new CustomEvent('de:doc-enhanced'));
    return;
  }

  if (isCheatsheetRoute(route.path)) {
    if (!docRoot.querySelector('.de-acc-section')) {
      delete docRoot.dataset.deCheatsheetEnhanced;
    }
    enhanceCheatsheetSections(docRoot);
    revealCurrentHashTarget();
    window.dispatchEvent(new CustomEvent('de:doc-enhanced'));
  }
}

function scheduleEnhancements(): void {
  void nextTick(() => {
    applyEnhancements();
  });
}

function onHashChange(): void {
  revealCurrentHashTarget();
}

onContentUpdated(() => {
  scheduleEnhancements();
});

onMounted(() => {
  scheduleEnhancements();
  if (typeof window !== 'undefined') {
    window.addEventListener('hashchange', onHashChange);
  }
});

onUnmounted(() => {
  if (typeof window !== 'undefined') {
    window.removeEventListener('hashchange', onHashChange);
  }
});

watch(
  () => route.path,
  () => {
    scheduleEnhancements();
  },
);
</script>

<template>
  <span hidden aria-hidden="true" data-de-enhancer-anchor></span>
</template>
