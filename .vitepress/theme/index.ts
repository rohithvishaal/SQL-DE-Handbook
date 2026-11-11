import DefaultTheme from 'vitepress/theme';
import { h } from 'vue';
import type { Theme } from 'vitepress';
import ClozeDrill from './components/ClozeDrill.vue';
import DialectBlock from './components/DialectBlock.vue';
import DocEnhancer from './components/DocEnhancer.vue';
import DocMiniMapSlot from './components/DocMiniMapSlot.vue';
import HandbookHud from './components/HandbookHud.vue';
import ModuleRail from './components/ModuleRail.vue';
import TodayHub from './components/TodayHub.vue';
import { getSharedHandbookStore, HANDBOOK_STORE_KEY } from './composables/useHandbookStore';
import './custom.css';

const theme: Theme = {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'nav-bar-content-after': () => h(HandbookHud),
      'sidebar-nav-before': () => h(ModuleRail),
      'aside-outline-before': () => h(DocMiniMapSlot, { variant: 'aside' }),
      'doc-after': () => [h(DocEnhancer), h(DocMiniMapSlot, { variant: 'compact' })],
    });
  },
  enhanceApp({ app }) {
    app.provide(HANDBOOK_STORE_KEY, getSharedHandbookStore());
    app.component('ClozeDrill', ClozeDrill);
    app.component('DialectBlock', DialectBlock);
    app.component('TodayHub', TodayHub);
  },
};

export default theme;
