import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import {
  collectMiniMapSections,
  computeScrollProgress,
  findActiveSectionId,
  type MiniMapSection,
} from './sectionMiniMap';
import SectionMiniMap from '../theme/components/SectionMiniMap.vue';

describe('Right-Side Section Mini-Map (helpers)', () => {
  it('extracts h2 and h3 headings with ids, ignores h1/badges/anchors, and sets tabindex="-1"', () => {
    const root = document.createElement('div');
    root.innerHTML = `
      <h1 id="title">Module 1</h1>
      <h2 id="1-core-operations">1. Core Operations <a class="header-anchor" href="#1-core-operations">#</a></h2>
      <h3 id="select">SELECT <span class="VPBadge">ANSI</span> <a class="header-anchor" href="#select">#</a></h3>
      <h3>Heading Without ID</h3>
      <h2 id="ignored" class="ignore-header">Ignored</h2>
      <h3 id="where">WHERE</h3>
    `;

    const sections = collectMiniMapSections(root);

    expect(sections.map((s) => ({ id: s.id, level: s.level, title: s.title, href: s.href }))).toEqual([
      { id: '1-core-operations', level: 2, title: '1. Core Operations', href: '#1-core-operations' },
      { id: 'select', level: 3, title: 'SELECT', href: '#select' },
      { id: 'where', level: 3, title: 'WHERE', href: '#where' },
    ]);

    expect(root.querySelector('[id="1-core-operations"]')?.getAttribute('tabindex')).toBe('-1');
    expect(root.querySelector('[id="select"]')?.getAttribute('tabindex')).toBe('-1');
    for (const s of sections) {
      expect(s.spanRatio).toBeGreaterThanOrEqual(0.2);
      expect(s.spanRatio).toBeLessThanOrEqual(1);
    }
  });

  it('computes clamped document scroll progress and active section by offset or bottom', () => {
    expect(computeScrollProgress(0, 2000, 800)).toBe(0);
    expect(computeScrollProgress(600, 2000, 800)).toBe(50);
    expect(computeScrollProgress(1200, 2000, 800)).toBe(100);
    expect(computeScrollProgress(0, 600, 800)).toBe(100);

    const offsets = [
      { id: 'intro', top: 100 },
      { id: 'windows', top: 700 },
      { id: 'summary', top: 1500 },
    ];
    expect(findActiveSectionId(offsets, 0, 80, 800, 2000)).toBe('intro');
    expect(findActiveSectionId(offsets, 650, 80, 800, 2000)).toBe('windows');
    // At very bottom of viewport, highlight last section even if short
    expect(findActiveSectionId(offsets, 1200, 80, 800, 2000)).toBe('summary');
  });
});

describe('Right-Side Section Mini-Map (component)', () => {
  const sampleSections: MiniMapSection[] = [
    { id: 'core-ops', href: '#core-ops', title: '1. Core Operations', level: 2, spanRatio: 0.4, offsetRatio: 0.05 },
    { id: 'select', href: '#select', title: 'SELECT', level: 3, spanRatio: 1, offsetRatio: 0.25 },
    { id: 'where', href: '#where', title: 'WHERE', level: 3, spanRatio: 0.65, offsetRatio: 0.7 },
  ];

  it('renders hierarchical links, proportional mini-map bars, and updates active anchor + aria-current on jump', async () => {
    const targetHeading = document.createElement('h3');
    targetHeading.id = 'where';
    targetHeading.tabIndex = -1;
    const scrollIntoViewMock = vi.fn();
    targetHeading.scrollIntoView = scrollIntoViewMock;
    document.body.appendChild(targetHeading);

    try {
      const wrapper = mount(SectionMiniMap, {
        props: { sections: sampleSections, variant: 'aside' },
      });

      const nav = wrapper.get('nav[aria-label="Section mini-map"]');
      const links = nav.findAll('a.de-minimap-link');
      expect(links).toHaveLength(3);
      expect(links[0].attributes('aria-current')).toBe('true');
      expect(links[1].attributes('data-level')).toBe('3');
      expect(wrapper.findAll('.de-minimap-span')).toHaveLength(3);

      await links[2].trigger('click');

      expect(links[2].attributes('aria-current')).toBe('true');
      expect(links[2].classes()).toContain('target-current');
      expect(links[0].attributes('aria-current')).toBe('false');
      expect(wrapper.text()).toContain('3 / 3');
      expect(scrollIntoViewMock).toHaveBeenCalledTimes(1);
    } finally {
      targetHeading.remove();
    }
  });

  it('supports Top and Bottom quick-jump controls and hides cleanly when disabled or empty', async () => {
    const scrollToSpy = vi.spyOn(window, 'scrollTo').mockImplementation(() => {});

    try {
      const hiddenWrapper = mount(SectionMiniMap, {
        props: { sections: sampleSections, disabled: true },
      });
      expect(hiddenWrapper.find('nav').exists()).toBe(false);

      const emptyWrapper = mount(SectionMiniMap, {
        props: { sections: [] },
      });
      expect(emptyWrapper.find('nav').exists()).toBe(false);

      const wrapper = mount(SectionMiniMap, {
        props: { sections: sampleSections, variant: 'aside' },
      });

      await wrapper.get('[data-testid="minimap-top-btn"]').trigger('click');
      await wrapper.get('[data-testid="minimap-bottom-btn"]').trigger('click');
      expect(scrollToSpy).toHaveBeenCalledTimes(2);
    } finally {
      scrollToSpy.mockRestore();
    }
  });

  it('renders compact popover mini-map trigger and panel for narrower viewports', async () => {
    const wrapper = mount(SectionMiniMap, {
      props: { sections: sampleSections, variant: 'compact' },
    });

    const trigger = wrapper.get('[data-testid="minimap-compact-toggle"]');
    expect(trigger.attributes('popovertarget')).toBeTruthy();

    const panel = wrapper.get(`#${trigger.attributes('popovertarget')}`);
    expect(panel.attributes('popover')).toBe('auto');
    expect(panel.findAll('a.de-minimap-link')).toHaveLength(3);
  });
});
