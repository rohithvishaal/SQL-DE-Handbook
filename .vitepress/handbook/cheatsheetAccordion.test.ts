import { describe, expect, it } from 'vitest';
import { collectMiniMapSections } from './sectionMiniMap';
import { enhanceCheatsheetSections, revealAccordionTarget } from './cheatsheetAccordion';

describe('Cheatsheet Section Dropdowns (heading-preserving accordion)', () => {
  it('keeps Table of Contents open, collapses content sections by default, syncs Expand/Collapse all, and reveals targets', () => {
    const doc = document.createElement('div');
    doc.innerHTML = `
      <h1 id="module-1">Module 1</h1>
      <blockquote>Summary quote</blockquote>
      <h2 id="table-of-contents">Table of Contents <a class="header-anchor" href="#table-of-contents">#</a></h2>
      <ol><li><a href="#1-core-operations">Core Operations</a></li></ol>
      <hr />
      <h2 id="1-core-operations">1. Core Operations <a class="header-anchor" href="#1-core-operations">#</a></h2>
      <h3 id="select">SELECT <a class="header-anchor" href="#select">#</a></h3>
      <p>Select retrieves columns.</p>
      <h3 id="where">WHERE <a class="header-anchor" href="#where">#</a></h3>
      <p>Where filters rows.</p>
      <hr />
      <h2 id="2-joins">2. Joins <a class="header-anchor" href="#2-joins">#</a></h2>
      <p>Join overview.</p>
    `;

    enhanceCheatsheetSections(doc);

    // Table of Contents stays visible outside accordion
    expect(doc.querySelector('[id="table-of-contents"] button.de-acc-trigger')).toBeNull();

    // Content h2 sections wrap trigger button inside h2 (permalink stays outside button)
    const h2Core = doc.querySelector('[id="1-core-operations"]')!;
    const triggerCore = h2Core.querySelector<HTMLButtonElement>('button.de-acc-trigger')!;
    expect(triggerCore).toBeTruthy();
    expect(h2Core.querySelector('a.header-anchor')?.closest('button')).toBeNull();
    expect(triggerCore.getAttribute('aria-expanded')).toBe('false');

    const panelId = triggerCore.getAttribute('aria-controls')!;
    const panelCore = doc.querySelector<HTMLElement>(`[id="${panelId}"]`)!;
    expect(panelCore.getAttribute('hidden')).toBe('until-found');

    // Right-Side Section Mini-Map ignores .de-acc-count / chevron badges inside heading buttons
    const miniSections = collectMiniMapSections(doc);
    expect(miniSections.find((s) => s.id === '1-core-operations')?.title).toBe('1. Core Operations');
    expect(miniSections.find((s) => s.id === 'where')?.title).toBe('WHERE');

    // Toggle open
    triggerCore.click();
    expect(triggerCore.getAttribute('aria-expanded')).toBe('true');
    expect(panelCore.hasAttribute('hidden')).toBe(false);

    // Toggle Expand all / Collapse all
    const toggleAll = doc.querySelector<HTMLButtonElement>('[data-testid="cheatsheet-toggle-all"]')!;
    expect(toggleAll.getAttribute('aria-expanded')).toBe('false');
    toggleAll.click();
    expect(toggleAll.getAttribute('aria-expanded')).toBe('true');

    const triggerJoins = doc.querySelector<HTMLButtonElement>('[id="2-joins"] button.de-acc-trigger')!;
    expect(triggerJoins.getAttribute('aria-expanded')).toBe('true');

    // Collapse all, then reveal deep subsection #where cleanly (as Mini-Map jump does)
    toggleAll.click();
    expect(triggerCore.getAttribute('aria-expanded')).toBe('false');

    const whereHeading = doc.querySelector('[id="where"]')!;
    revealAccordionTarget(whereHeading);
    expect(triggerCore.getAttribute('aria-expanded')).toBe('true');
    expect(panelCore.hasAttribute('hidden')).toBe(false);
  });
});
