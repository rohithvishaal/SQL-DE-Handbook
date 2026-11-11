<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, useId, watch } from 'vue';
import { revealAccordionTarget } from '../../handbook/cheatsheetAccordion';
import {
  collectMiniMapSections,
  computeScrollProgress,
  findActiveSectionId,
  getDocumentTop,
  type MiniMapSection,
} from '../../handbook/sectionMiniMap';

const props = withDefaults(
  defineProps<{
    sections?: MiniMapSection[];
    variant?: 'aside' | 'compact';
    disabled?: boolean;
  }>(),
  {
    sections: undefined,
    variant: 'aside',
    disabled: false,
  },
);

const popoverId = `de-minimap-${useId()}`;
const panelEl = ref<HTMLElement | null>(null);
const scrollerEl = ref<HTMLElement | null>(null);
const listEl = ref<HTMLElement | null>(null);

const discoveredSections = ref<MiniMapSection[]>([]);
const activeId = ref<string | null>(null);
const progress = ref(0);
const isCompactOpen = ref(false);

const supportsPopover = ref(false);
const supportsScrollTargetGroup = ref(false);
const supportsScrollTimeline = ref(false);
const prefersReducedMotion = ref(false);

const effectiveSections = computed<MiniMapSection[]>(
  () => props.sections ?? discoveredSections.value,
);

const isVisible = computed(
  () => !props.disabled && effectiveSections.value.length > 0,
);

const activeIndex = computed(() => {
  if (effectiveSections.value.length === 0) return 0;
  const idx = effectiveSections.value.findIndex((s) => s.id === activeId.value);
  return idx >= 0 ? idx + 1 : 1;
});

const activePositionLabel = computed(
  () => `${activeIndex.value} / ${effectiveSections.value.length}`,
);

const progressFillStyle = computed(() => {
  if (supportsScrollTimeline.value && !prefersReducedMotion.value) {
    return undefined;
  }
  return { transform: `scaleX(${progress.value / 100})` };
});

let observer: IntersectionObserver | null = null;
let rafId: number | null = null;
let motionQuery: MediaQueryList | null = null;

function readMotionPreference(): boolean {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
    return false;
  }
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

function getHeaderScrollOffset(): number {
  if (typeof window === 'undefined') return 80;
  const raw = window.getComputedStyle(document.documentElement).getPropertyValue('--vp-nav-height');
  const parsed = Number.parseFloat(raw);
  return Number.isFinite(parsed) && parsed > 0 ? parsed + 16 : 80;
}

function scrollBehavior(): ScrollBehavior {
  return prefersReducedMotion.value ? 'auto' : 'smooth';
}

function keepActiveItemVisible() {
  const scroller = scrollerEl.value;
  const list = listEl.value;
  if (!scroller || !list || !activeId.value) return;

  const activeLink = list.querySelector<HTMLElement>(
    `a[data-section-id="${CSS?.escape ? CSS.escape(activeId.value) : activeId.value}"]`,
  );
  if (!activeLink) return;

  const top = activeLink.offsetTop;
  const bottom = top + activeLink.offsetHeight;
  const viewTop = scroller.scrollTop;
  const viewBottom = viewTop + scroller.clientHeight;

  if (top < viewTop + 16) {
    scroller.scrollTop = Math.max(0, top - 16);
  } else if (bottom > viewBottom - 16) {
    scroller.scrollTop = Math.max(0, bottom - scroller.clientHeight + 16);
  }
}

function updateScrollMetrics() {
  if (typeof window === 'undefined' || typeof document === 'undefined') return;

  const docEl = document.documentElement;
  progress.value = computeScrollProgress(
    window.scrollY || 0,
    docEl?.scrollHeight ?? 0,
    window.innerHeight || 0,
  );

  if (effectiveSections.value.length === 0) return;

  if (!supportsScrollTargetGroup.value) {
    const offsets = effectiveSections.value
      .map((section) => {
        const target = document.getElementById(section.id);
        return target ? { id: section.id, top: getDocumentTop(target) } : null;
      })
      .filter((entry): entry is { id: string; top: number } => entry !== null);

    if (offsets.length > 0) {
      activeId.value = findActiveSectionId(
        offsets,
        window.scrollY || 0,
        getHeaderScrollOffset(),
        window.innerHeight || 0,
        docEl?.scrollHeight ?? 0,
      );
    }
  }
}

function syncFromTargetCurrent() {
  if (!supportsScrollTargetGroup.value || !listEl.value) return;
  try {
    const current = listEl.value.querySelector<HTMLElement>('a:target-current');
    const matchedId = current?.dataset.sectionId;
    if (matchedId) {
      activeId.value = matchedId;
    }
  } catch {
    // Environments lacking :target-current selector support safely ignore
  }
}

function disconnectObserver() {
  if (observer) {
    observer.disconnect();
    observer = null;
  }
}

function setupObserver() {
  disconnectObserver();
  if (
    supportsScrollTargetGroup.value ||
    typeof IntersectionObserver === 'undefined' ||
    typeof document === 'undefined' ||
    effectiveSections.value.length === 0
  ) {
    return;
  }

  observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting && entry.target.id) {
          activeId.value = entry.target.id;
        }
      }
    },
    { rootMargin: '-18% 0px -65% 0px', threshold: 0 },
  );

  for (const section of effectiveSections.value) {
    const el = document.getElementById(section.id);
    if (el) observer.observe(el);
  }
}

function syncInitialActive() {
  const list = effectiveSections.value;
  if (list.length === 0) {
    activeId.value = null;
    return;
  }
  const hashId =
    typeof window !== 'undefined' && window.location.hash.length > 1
      ? decodeURIComponent(window.location.hash.slice(1))
      : null;

  if (hashId && list.some((s) => s.id === hashId)) {
    activeId.value = hashId;
  } else if (!activeId.value || !list.some((s) => s.id === activeId.value)) {
    activeId.value = list[0].id;
  }
}

function closeCompactPopover() {
  if (props.variant !== 'compact') return;
  const panel = panelEl.value as (HTMLElement & { hidePopover?: () => void }) | null;
  if (supportsPopover.value && panel && typeof panel.hidePopover === 'function') {
    try {
      panel.hidePopover();
    } catch {
      // Ignore if already closed
    }
  }
  isCompactOpen.value = false;
}

function onCompactButtonClick() {
  if (!supportsPopover.value) {
    isCompactOpen.value = !isCompactOpen.value;
  }
}

function onPopoverToggle(event: Event) {
  const toggleEvent = event as ToggleEvent;
  if (toggleEvent && typeof toggleEvent.newState === 'string') {
    isCompactOpen.value = toggleEvent.newState === 'open';
  }
}

function onSelectSection(section: MiniMapSection, event: MouseEvent) {
  if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) {
    return;
  }
  event.preventDefault();

  activeId.value = section.id;
  const target = typeof document !== 'undefined' ? document.getElementById(section.id) : null;
  if (target) {
    revealAccordionTarget(target);
    if (!target.hasAttribute('tabindex')) {
      target.setAttribute('tabindex', '-1');
    }
    target.scrollIntoView?.({ behavior: scrollBehavior(), block: 'start' });
    if (typeof (target as HTMLElement).focus === 'function') {
      (target as HTMLElement).focus({ preventScroll: true });
    }
  }

  if (typeof window !== 'undefined' && window.history?.replaceState) {
    window.history.replaceState(null, '', section.href);
  }

  closeCompactPopover();
}

function jumpTo(edge: 'top' | 'bottom') {
  const list = effectiveSections.value;
  if (typeof window !== 'undefined' && typeof document !== 'undefined') {
    const targetTop =
      edge === 'top'
        ? 0
        : Math.max(0, (document.documentElement?.scrollHeight ?? 0) - (window.innerHeight || 0));
    window.scrollTo({ top: targetTop, behavior: scrollBehavior() });
  }
  if (list.length > 0) {
    activeId.value = edge === 'top' ? list[0].id : list[list.length - 1].id;
  }
  closeCompactPopover();
}

function onScroll() {
  if (typeof window === 'undefined') {
    updateScrollMetrics();
    return;
  }
  if (rafId !== null) return;
  rafId = window.requestAnimationFrame(() => {
    rafId = null;
    updateScrollMetrics();
  });
}

function onWindowKeydown(event: KeyboardEvent) {
  if (props.variant === 'compact' && !supportsPopover.value && isCompactOpen.value && event.key === 'Escape') {
    isCompactOpen.value = false;
  }
}

function onMotionChange(event: MediaQueryListEvent) {
  prefersReducedMotion.value = event.matches;
}

watch(
  effectiveSections,
  () => {
    syncInitialActive();
    void nextTick(() => {
      setupObserver();
      updateScrollMetrics();
    });
  },
  { immediate: true },
);

watch(activeId, () => {
  void nextTick(keepActiveItemVisible);
});

function supportsRealCss(condition: string): boolean {
  if (typeof CSS === 'undefined' || typeof CSS.supports !== 'function') return false;
  // Blind DOM test stubs (e.g. happy-dom) return true for unknown properties.
  if (CSS.supports('mwg-unsupported-probe: 1')) return false;
  return CSS.supports(condition);
}

onMounted(() => {
  supportsPopover.value =
    typeof HTMLElement !== 'undefined' && Object.hasOwn(HTMLElement.prototype, 'popover');
  supportsScrollTargetGroup.value = supportsRealCss('scroll-target-group: auto');
  supportsScrollTimeline.value = supportsRealCss('animation-timeline: scroll()');
  prefersReducedMotion.value = readMotionPreference();

  if (props.sections === undefined && typeof document !== 'undefined') {
    const docRoot = document.querySelector('.VPDoc .vp-doc') ?? document.body;
    discoveredSections.value = collectMiniMapSections(docRoot);
  }

  syncInitialActive();
  setupObserver();
  updateScrollMetrics();

  if (typeof window !== 'undefined') {
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('keydown', onWindowKeydown);
    if (typeof window.matchMedia === 'function') {
      motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
      motionQuery.addEventListener?.('change', onMotionChange);
    }
  }
  if (typeof document !== 'undefined' && supportsScrollTargetGroup.value) {
    document.addEventListener('scrollend', syncFromTargetCurrent, { passive: true });
  }
});

onUnmounted(() => {
  disconnectObserver();
  if (typeof window !== 'undefined') {
    window.removeEventListener('scroll', onScroll);
    window.removeEventListener('keydown', onWindowKeydown);
    if (rafId !== null) {
      window.cancelAnimationFrame(rafId);
      rafId = null;
    }
  }
  motionQuery?.removeEventListener?.('change', onMotionChange);
  if (typeof document !== 'undefined') {
    document.removeEventListener('scrollend', syncFromTargetCurrent);
  }
});
</script>

<template>
  <div
    v-if="isVisible"
    :class="variant === 'compact' ? 'de-minimap-mobile' : 'de-minimap-desktop'"
  >
    <button
      v-if="variant === 'compact'"
      type="button"
      class="de-minimap-fab de-num"
      data-testid="minimap-compact-toggle"
      :popovertarget="popoverId"
      :aria-expanded="String(isCompactOpen)"
      aria-label="Open section mini-map"
      @click="onCompactButtonClick"
    >
      <span>Mini-Map</span>
      <span aria-hidden="true">·</span>
      <span>{{ activePositionLabel }}</span>
      <span aria-hidden="true">·</span>
      <span>{{ progress }}%</span>
    </button>

    <div
      :id="variant === 'compact' ? popoverId : undefined"
      ref="panelEl"
      :popover="variant === 'compact' ? 'auto' : undefined"
      :class="
        variant === 'compact'
          ? ['de-minimap-popover', { 'de-popover-open': !supportsPopover && isCompactOpen }]
          : 'de-minimap-aside'
      "
      @toggle="onPopoverToggle"
    >
      <nav class="de-minimap" aria-label="Section mini-map">
        <div class="de-minimap-head">
          <span class="de-minimap-eyebrow">Mini-Map</span>
          <span class="de-minimap-meta de-num">
            {{ activePositionLabel }} · {{ progress }}%
          </span>
        </div>

        <div class="de-minimap-progress-track" aria-hidden="true">
          <span class="de-minimap-progress-fill" :style="progressFillStyle" />
        </div>

        <div ref="scrollerEl" class="de-minimap-scroller">
          <ul ref="listEl" class="de-minimap-list">
            <li
              v-for="section in effectiveSections"
              :key="section.id"
              class="de-minimap-item"
            >
              <a
                :href="section.href"
                class="de-minimap-link"
                :class="{ 'target-current': !supportsScrollTargetGroup && section.id === activeId }"
                :data-level="section.level"
                :data-section-id="section.id"
                :aria-current="section.id === activeId ? 'true' : 'false'"
                @click="onSelectSection(section, $event)"
              >
                <span class="de-minimap-title">{{ section.title }}</span>
                <span class="de-minimap-span" aria-hidden="true">
                  <span
                    class="de-minimap-span-fill"
                    :style="{ transform: `scaleX(${section.spanRatio})` }"
                  />
                </span>
              </a>
            </li>
          </ul>
        </div>

        <div class="de-minimap-foot">
          <button
            type="button"
            class="de-minimap-jump"
            data-testid="minimap-top-btn"
            @click="jumpTo('top')"
          >
            ↑ Top
          </button>
          <button
            type="button"
            class="de-minimap-jump"
            data-testid="minimap-bottom-btn"
            @click="jumpTo('bottom')"
          >
            ↓ Bottom
          </button>
        </div>
      </nav>
    </div>
  </div>
</template>
