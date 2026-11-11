/**
 * Pure utilities for extracting structured heading sections, measuring visual
 * mini-map proportions, and calculating scrollspy/progress state.
 */

export interface MiniMapSection {
  id: string;
  href: string;
  title: string;
  level: 2 | 3;
  /** Normalized section span proportion [0.2..1.0] for mini-map density bars */
  spanRatio: number;
  /** Cumulative start position [0..1] across the document */
  offsetRatio: number;
}

export interface HeadingOffset {
  id: string;
  top: number;
}

const IGNORED_CHILD_CLASSES = /\b(?:VPBadge|header-anchor|footnote-ref|ignore-header|de-acc-count|de-acc-chevron|de-quiz-status)\b/;

/**
 * Serialize readable heading text while skipping anchor `#` links and badges.
 */
function serializeHeadingText(root: Element): string {
  let text = '';
  for (const node of Array.from(root.childNodes)) {
    if (node.nodeType === 1) {
      const el = node as Element;
      const cls = typeof el.className === 'string' ? el.className : '';
      if (IGNORED_CHILD_CLASSES.test(cls)) continue;
      text += serializeHeadingText(el);
    } else if (node.nodeType === 3) {
      text += node.textContent ?? '';
    }
  }
  return text.trim();
}

/**
 * Read vertical offset of an element relative to the page top when laid out.
 */
export function getDocumentTop(el: Element): number {
  if (typeof window === 'undefined' || typeof el.getBoundingClientRect !== 'function') {
    return 0;
  }
  const rect = el.getBoundingClientRect();
  return rect.top + (window.scrollY || 0);
}

/**
 * Scan `root` for focusable section targets (`h2[id], h3[id]`), assign
 * `tabindex="-1"` when missing so jumped headings accept keyboard focus,
 * and return normalized mini-map entries.
 */
export function collectMiniMapSections(root: ParentNode | null): MiniMapSection[] {
  if (!root) return [];

  const rawHeadings = Array.from(root.querySelectorAll('h2[id], h3[id]')).filter((el) => {
    if (!el.id || el.classList.contains('ignore-header')) return false;
    return serializeHeadingText(el).length > 0;
  });

  if (rawHeadings.length === 0) return [];

  const measured = rawHeadings.map((el) => {
    if (!el.hasAttribute('tabindex')) {
      el.setAttribute('tabindex', '-1');
    }
    const level: 2 | 3 = el.tagName.toUpperCase() === 'H2' ? 2 : 3;
    const title = serializeHeadingText(el);
    return {
      id: el.id,
      href: `#${el.id}`,
      title,
      level,
      top: getDocumentTop(el),
    };
  });

  const firstTop = measured[0]?.top ?? 0;
  const docHeight =
    typeof document !== 'undefined' && document.documentElement
      ? Math.max(document.documentElement.scrollHeight, 0)
      : 0;
  const lastTop = measured[measured.length - 1]?.top ?? 0;
  const totalMeasuredSpan = docHeight > lastTop ? docHeight - firstTop : lastTop - firstTop;

  if (totalMeasuredSpan <= 0) {
    // Fallback proportions when layout geometry is unavailable (e.g. happy-dom / SSR)
    const denominator = Math.max(1, measured.length - 1);
    return measured.map((item, idx) => ({
      id: item.id,
      href: item.href,
      title: item.title,
      level: item.level,
      spanRatio: item.level === 2 ? 0.65 : 0.45,
      offsetRatio: Number((idx / denominator).toFixed(3)),
    }));
  }

  const rawSpans = measured.map((item, idx) => {
    const nextTop = idx + 1 < measured.length ? measured[idx + 1].top : firstTop + totalMeasuredSpan;
    return Math.max(0, nextTop - item.top);
  });
  const maxSpan = Math.max(...rawSpans, 1);

  return measured.map((item, idx) => {
    const normalizedSpan = Math.min(1, Math.max(0.2, rawSpans[idx] / maxSpan));
    const offsetRatio = Math.min(1, Math.max(0, (item.top - firstTop) / totalMeasuredSpan));
    return {
      id: item.id,
      href: item.href,
      title: item.title,
      level: item.level,
      spanRatio: Number(normalizedSpan.toFixed(3)),
      offsetRatio: Number(offsetRatio.toFixed(3)),
    };
  });
}

/**
 * Calculate clamped integer reading progress percentage [0..100].
 */
export function computeScrollProgress(
  scrollY: number,
  scrollHeight: number,
  innerHeight: number,
): number {
  const scrollable = scrollHeight - innerHeight;
  if (scrollable <= 0) return 100;
  return Math.round(Math.min(1, Math.max(0, scrollY / scrollable)) * 100);
}

/**
 * Determine which heading id corresponds to the current scroll position.
 */
export function findActiveSectionId(
  items: HeadingOffset[],
  scrollY: number,
  scrollOffset: number,
  innerHeight: number,
  docHeight: number,
): string | null {
  if (items.length === 0) return null;

  const sorted = [...items].sort((a, b) => a.top - b.top);
  if (docHeight > innerHeight && scrollY + innerHeight >= docHeight - 2) {
    return sorted[sorted.length - 1].id;
  }

  const threshold = scrollY + scrollOffset + 12;
  let activeId = sorted[0].id;
  for (const item of sorted) {
    if (item.top > threshold) break;
    activeId = item.id;
  }
  return activeId;
}
