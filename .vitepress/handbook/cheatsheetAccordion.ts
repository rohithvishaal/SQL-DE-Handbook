/**
 * Progressive heading-preserving accordion enhancement for Cheat Sheet pages (`cheatsheets/*.md`).
 * Keeps original `h2`/`h3` semantics, #ids, permalink anchors outside triggers,
 * supports `beforematch` Ctrl+F reveal, and syncs "Expand all / Collapse all".
 */

interface AccordionItem {
  trigger: HTMLButtonElement;
  panel: HTMLElement;
}

function getCleanHeadingLabel(heading: Element): string {
  let label = '';
  for (const node of Array.from(heading.childNodes)) {
    if (node.nodeType === 1) {
      const el = node as Element;
      const cls = typeof el.className === 'string' ? el.className : '';
      if (/\b(?:header-anchor|VPBadge|footnote-ref|de-acc-count|de-acc-chevron)\b/.test(cls)) {
        continue;
      }
      label += el.textContent ?? '';
    } else if (node.nodeType === 3) {
      label += node.textContent ?? '';
    }
  }
  return label.trim();
}

function setAccordionExpanded(item: AccordionItem, expanded: boolean): void {
  item.trigger.setAttribute('aria-expanded', String(expanded));
  if (expanded) {
    item.panel.removeAttribute('hidden');
  } else {
    item.panel.setAttribute('hidden', 'until-found');
  }
}

function createAccordionTrigger(
  doc: Document,
  heading: Element,
  panelId: string,
  expanded: boolean,
  badgeText?: string,
): HTMLButtonElement {
  const labelText = getCleanHeadingLabel(heading);
  const anchorEl = Array.from(heading.children).find(
    (el): el is HTMLAnchorElement => el.tagName.toUpperCase() === 'A' && el.classList.contains('header-anchor'),
  );

  // Clear non-anchor heading text nodes before inserting the trigger button
  for (const child of Array.from(heading.childNodes)) {
    if (child !== anchorEl) child.remove();
  }

  const trigger = doc.createElement('button');
  trigger.type = 'button';
  trigger.className = 'de-acc-trigger';
  trigger.setAttribute('aria-expanded', String(expanded));
  trigger.setAttribute('aria-controls', panelId);

  const chevron = doc.createElement('span');
  chevron.className = 'de-acc-chevron';
  chevron.setAttribute('aria-hidden', 'true');

  const labelSpan = doc.createElement('span');
  labelSpan.className = 'de-acc-label';
  labelSpan.textContent = labelText;

  trigger.append(chevron, labelSpan);

  if (badgeText) {
    const countPill = doc.createElement('span');
    countPill.className = 'de-acc-count de-num';
    countPill.textContent = badgeText;
    trigger.append(countPill);
  }

  if (anchorEl) {
    heading.insertBefore(trigger, anchorEl);
  } else {
    heading.append(trigger);
  }

  heading.classList.add('de-acc-heading');
  return trigger;
}

function syncToggleAllState(docRoot: Element): void {
  const toggleAll = docRoot.querySelector<HTMLButtonElement>('[data-testid="cheatsheet-toggle-all"]');
  if (!toggleAll) return;

  const h2Triggers = Array.from(docRoot.querySelectorAll('.de-acc-section'))
    .map((sec) => {
      const h2 = Array.from(sec.children).find((el) => el.tagName.toUpperCase() === 'H2');
      return h2
        ? Array.from(h2.children).find(
            (el): el is HTMLButtonElement =>
              el.tagName.toUpperCase() === 'BUTTON' && el.classList.contains('de-acc-trigger'),
          )
        : undefined;
    })
    .filter((btn): btn is HTMLButtonElement => Boolean(btn));
  const allOpen = h2Triggers.length > 0 && h2Triggers.every((btn) => btn.getAttribute('aria-expanded') === 'true');
  toggleAll.setAttribute('aria-expanded', String(allOpen));
}

function wrapSubsectionAccordions(docRoot: Element, body: HTMLElement): void {
  const doc = body.ownerDocument;
  const subHeadings = Array.from(body.children).filter(
    (el): el is HTMLHeadingElement => el.tagName.toUpperCase() === 'H3',
  );
  for (const subHeading of subHeadings) {
    const nodes: Node[] = [];
    let cursor: ChildNode | null = subHeading.nextSibling;
    while (cursor) {
      const next = cursor.nextSibling;
      if (cursor instanceof Element && cursor.tagName.toUpperCase() === 'H3') break;
      nodes.push(cursor);
      cursor = next;
    }

    const section = doc.createElement('section');
    section.className = 'de-acc-sub';
    if (subHeading.id) {
      section.setAttribute('aria-labelledby', subHeading.id);
    }

    const panelId = `de-subpanel-${subHeading.id || Math.random().toString(36).slice(2, 8)}`;
    const panel = doc.createElement('div');
    panel.id = panelId;
    panel.className = 'de-acc-panel';

    const innerBody = doc.createElement('div');
    innerBody.className = 'de-acc-sub-body';
    for (const node of nodes) {
      if (node instanceof Element && node.tagName.toUpperCase() === 'HR') {
        node.remove();
        continue;
      }
      innerBody.append(node);
    }
    panel.append(innerBody);

    subHeading.parentElement?.insertBefore(section, subHeading);
    section.append(subHeading, panel);

    const trigger = createAccordionTrigger(doc, subHeading, panelId, true);
    const item: AccordionItem = { trigger, panel };

    trigger.addEventListener('click', () => {
      const nextOpen = trigger.getAttribute('aria-expanded') !== 'true';
      setAccordionExpanded(item, nextOpen);
    });
    panel.addEventListener('beforematch', () => {
      setAccordionExpanded(item, true);
      syncToggleAllState(docRoot);
    });
  }
}

/**
 * Reveal all collapsed ancestor accordion panels enclosing `target` cleanly
 * before scrolling to an anchor link, Mini-Map selection, or Ctrl+F match.
 */
export function revealAccordionTarget(target: Element | null): void {
  if (!target) return;
  let current: Element | null = target;
  const root = target.closest('.vp-doc');

  while (current) {
    if (current.classList.contains('de-acc-panel') && current.id) {
      const escapedId = typeof CSS !== 'undefined' && CSS.escape ? CSS.escape(current.id) : current.id;
      const scope = current.parentElement ?? document;
      const trigger = scope.querySelector<HTMLButtonElement>(`button[aria-controls="${escapedId}"]`);
      if (trigger) {
        trigger.setAttribute('aria-expanded', 'true');
      }
      (current as HTMLElement).removeAttribute('hidden');
    }
    current = current.parentElement;
  }

  if (root) {
    syncToggleAllState(root);
  }
}

/**
 * Convert cheat sheet content `h2` chapters (excluding Table of Contents) into
 * collapsed-by-default accessible dropdowns with an Expand All / Collapse All toolbar.
 */
export function enhanceCheatsheetSections(docRoot: Element | null): void {
  if (!docRoot || (docRoot as HTMLElement).dataset.deCheatsheetEnhanced === 'true') {
    return;
  }

  const doc = docRoot.ownerDocument;
  const allH2 = Array.from(docRoot.querySelectorAll<HTMLHeadingElement>('h2'));
  const sectionHeadings = allH2.filter((h2) => h2.id !== 'table-of-contents');
  if (sectionHeadings.length === 0) return;

  // Insert Expand/Collapse All button bar right before first collapsible h2
  const toolbar = doc.createElement('div');
  toolbar.className = 'de-acc-toolbar';

  const countLabel = doc.createElement('span');
  countLabel.className = 'de-acc-toolbar-note de-num';
  countLabel.textContent = `${sectionHeadings.length} sections collapsed by default`;

  const toggleAllBtn = doc.createElement('button');
  toggleAllBtn.type = 'button';
  toggleAllBtn.className = 'de-btn de-btn-subtle de-acc-toggle-all';
  toggleAllBtn.dataset.testid = 'cheatsheet-toggle-all';
  toggleAllBtn.setAttribute('aria-expanded', 'false');
  toggleAllBtn.innerHTML =
    '<span class="de-acc-expand-label">Expand all sections</span><span class="de-acc-collapse-label">Collapse all sections</span>';

  toolbar.append(countLabel, toggleAllBtn);
  sectionHeadings[0].parentElement?.insertBefore(toolbar, sectionHeadings[0]);

  const topItems: AccordionItem[] = [];

  for (const h2 of sectionHeadings) {
    const siblings: Node[] = [];
    let cursor: ChildNode | null = h2.nextSibling;
    while (cursor) {
      const next = cursor.nextSibling;
      if (cursor instanceof Element && cursor.tagName.toUpperCase() === 'H2') break;
      siblings.push(cursor);
      cursor = next;
    }

    const subTopicCount = siblings.filter(
      (node) => node instanceof Element && node.tagName.toUpperCase() === 'H3',
    ).length;

    const section = doc.createElement('section');
    section.className = 'de-acc-section';
    if (h2.id) {
      section.setAttribute('aria-labelledby', h2.id);
    }

    const panelId = `de-panel-${h2.id || Math.random().toString(36).slice(2, 8)}`;
    const panel = doc.createElement('div');
    panel.id = panelId;
    panel.className = 'de-acc-panel';
    panel.setAttribute('hidden', 'until-found');

    const body = doc.createElement('div');
    body.className = 'de-acc-body';
    for (const node of siblings) {
      if (node instanceof Element && node.tagName.toUpperCase() === 'HR' && node === siblings[siblings.length - 1]) {
        node.remove();
        continue;
      }
      body.append(node);
    }
    panel.append(body);

    h2.parentElement?.insertBefore(section, h2);
    section.append(h2, panel);

    const badge = subTopicCount > 0 ? `${subTopicCount} topics` : undefined;
    const trigger = createAccordionTrigger(doc, h2, panelId, false, badge);
    const item: AccordionItem = { trigger, panel };
    topItems.push(item);

    trigger.addEventListener('click', () => {
      const nextOpen = trigger.getAttribute('aria-expanded') !== 'true';
      setAccordionExpanded(item, nextOpen);
      syncToggleAllState(docRoot);
    });

    panel.addEventListener('beforematch', () => {
      setAccordionExpanded(item, true);
      syncToggleAllState(docRoot);
    });

    wrapSubsectionAccordions(docRoot, body);
  }

  toggleAllBtn.addEventListener('click', () => {
    const shouldExpand = toggleAllBtn.getAttribute('aria-expanded') !== 'true';
    for (const item of topItems) {
      setAccordionExpanded(item, shouldExpand);
      if (shouldExpand) {
        const subButtons = item.panel.querySelectorAll<HTMLButtonElement>('.de-acc-sub button.de-acc-trigger');
        for (const subBtn of subButtons) {
          const ctrlId = subBtn.getAttribute('aria-controls');
          const subPanel = ctrlId ? item.panel.querySelector<HTMLElement>(`[id="${ctrlId}"]`) : null;
          if (subPanel) {
            setAccordionExpanded({ trigger: subBtn, panel: subPanel }, true);
          }
        }
      }
    }
    syncToggleAllState(docRoot);
  });

  // Auto-expand target section when clicking any Table of Contents / internal #anchor link
  docRoot.addEventListener('click', (event) => {
    const anchor = (event.target as Element | null)?.closest<HTMLAnchorElement>('a[href^="#"]');
    if (!anchor || anchor.classList.contains('header-anchor')) return;
    const rawId = decodeURIComponent(anchor.getAttribute('href')?.slice(1) ?? '');
    if (!rawId) return;
    const target =
      typeof document !== 'undefined'
        ? document.getElementById(rawId)
        : docRoot.querySelector(`[id="${rawId}"]`);
    if (target) {
      revealAccordionTarget(target);
    }
  });

  (docRoot as HTMLElement).dataset.deCheatsheetEnhanced = 'true';
}
