import m1SolutionsRaw from '../../exercises/01-foundations/solutions.md?raw';
import m2SolutionsRaw from '../../exercises/02-window-functions/solutions.md?raw';
import m3SolutionsRaw from '../../exercises/03-de-patterns/solutions.md?raw';
import m4SolutionsRaw from '../../exercises/04-cloud-dw/solutions.md?raw';
import m5SolutionsRaw from '../../exercises/05-performance/solutions.md?raw';

export type McqOptionLetter = 'A' | 'B' | 'C' | 'D';

export interface ParsedQuestionSolution {
  questionNumber: number;
  title: string;
  correctOption?: McqOptionLetter;
  answerLine?: string;
  explanationHtml: string;
}

const SOLUTIONS_BY_TRACK: ReadonlyArray<{ match: string; raw: string }> = [
  { match: '/exercises/01-foundations/quiz', raw: m1SolutionsRaw },
  { match: '/exercises/02-window-functions/quiz', raw: m2SolutionsRaw },
  { match: '/exercises/03-de-patterns/quiz', raw: m3SolutionsRaw },
  { match: '/exercises/04-cloud-dw/quiz', raw: m4SolutionsRaw },
  { match: '/exercises/05-performance/quiz', raw: m5SolutionsRaw },
];

function escapeHtml(text: string): string {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function renderInlineMarkdown(raw: string): string {
  // Split around inline code spans so asterisks/brackets inside code aren't formatted
  const segments = raw.split(/(`[^`]+`)/g);
  return segments
    .map((segment) => {
      if (segment.startsWith('`') && segment.endsWith('`') && segment.length >= 2) {
        return `<code>${escapeHtml(segment.slice(1, -1))}</code>`;
      }
      let out = escapeHtml(segment);
      out = out.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+|\.\.?\/[^)\s]+|#[^)\s]+)\)/g, '<a href="$2">$1</a>');
      out = out.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
      out = out.replace(/(^|[^*])\*([^*]+)\*(?!\*)/g, '$1<em>$2</em>');
      return out;
    })
    .join('');
}

function isTableSeparatorRow(line: string): boolean {
  return /^\|\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$/.test(line.trim());
}

function splitTableRow(line: string): string[] {
  return line
    .trim()
    .replace(/^\|/, '')
    .replace(/\|$/, '')
    .split('|')
    .map((cell) => cell.trim());
}

/**
 * Convert a constrained solution Markdown section into XSS-escaped semantic HTML.
 */
export function renderSolutionMarkdownToHtml(markdown: string): string {
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  const html: string[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trim();

    if (!trimmed || /^---+$/.test(trimmed)) {
      i += 1;
      continue;
    }

    // Fenced code block
    const fenceMatch = /^```([^\s]*)/.exec(trimmed);
    if (fenceMatch) {
      const codeLines: string[] = [];
      i += 1;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        codeLines.push(lines[i]);
        i += 1;
      }
      if (i < lines.length) i += 1;
      const lang = fenceMatch[1] ? ` data-lang="${escapeHtml(fenceMatch[1])}"` : '';
      html.push(`<pre class="de-code"${lang}><code>${escapeHtml(codeLines.join('\n'))}</code></pre>`);
      continue;
    }

    // Subheadings (## through ######) mapped cleanly to <h4> inside panel
    const headingMatch = /^#{1,6}\s+(.+)$/.exec(trimmed);
    if (headingMatch) {
      html.push(`<h4 class="de-exp-subhead">${renderInlineMarkdown(headingMatch[1])}</h4>`);
      i += 1;
      continue;
    }

    // GitHub-style callout / blockquote
    if (trimmed.startsWith('>')) {
      const quoteLines: string[] = [];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        quoteLines.push(lines[i].trim().replace(/^>\s?/, ''));
        i += 1;
      }
      const alertMatch = /^\[!(TIP|WARNING|NOTE|IMPORTANT)\]\s*$/i.exec(quoteLines[0] ?? '');
      const kind = alertMatch ? alertMatch[1].toLowerCase() : 'note';
      const bodyLines = alertMatch ? quoteLines.slice(1) : quoteLines;
      const prefix = alertMatch ? `<strong class="de-exp-callout-title">${escapeHtml(alertMatch[1].toUpperCase())}</strong> ` : '';
      html.push(
        `<div class="de-exp-callout" data-kind="${kind}"><p>${prefix}${bodyLines.map(renderInlineMarkdown).join(' ')}</p></div>`,
      );
      continue;
    }

    // Markdown table
    if (trimmed.startsWith('|') && i + 1 < lines.length && isTableSeparatorRow(lines[i + 1])) {
      const headers = splitTableRow(lines[i]);
      i += 2;
      const rows: string[][] = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        rows.push(splitTableRow(lines[i]));
        i += 1;
      }
      const thead = `<thead><tr>${headers.map((h) => `<th scope="col">${renderInlineMarkdown(h)}</th>`).join('')}</tr></thead>`;
      const tbody = `<tbody>${rows
        .map((row) => `<tr>${row.map((cell) => `<td>${renderInlineMarkdown(cell)}</td>`).join('')}</tr>`)
        .join('')}</tbody>`;
      html.push(`<div class="de-exp-table-wrap"><table>${thead}${tbody}</table></div>`);
      continue;
    }

    // Bullet / ordered list (handles shallow nested bullets)
    if (/^[-*]\s+/.test(trimmed) || /^\d+\.\s+/.test(trimmed)) {
      const isOrdered = /^\d+\.\s+/.test(trimmed);
      const tag = isOrdered ? 'ol' : 'ul';
      const items: string[] = [];
      while (i < lines.length) {
        const curTrim = lines[i].trim();
        if (!curTrim) break;
        const m = isOrdered ? /^\d+\.\s+(.*)$/.exec(curTrim) : /^[-*]\s+(.*)$/.exec(curTrim);
        if (!m && !/^\s{2,}[-*]\s+/.test(lines[i])) break;
        if (m) {
          items.push(`<li>${renderInlineMarkdown(m[1])}</li>`);
        } else {
          const nested = curTrim.replace(/^[-*]\s+/, '');
          if (items.length > 0) {
            items[items.length - 1] = items[items.length - 1].replace(
              /<\/li>$/,
              `<ul><li>${renderInlineMarkdown(nested)}</li></ul></li>`,
            );
          }
        }
        i += 1;
      }
      html.push(`<${tag}>${items.join('')}</${tag}>`);
      continue;
    }

    // Paragraph (stop cleanly on blank lines or block starters, and always advance at least one line)
    const paraLines: string[] = [];
    while (i < lines.length) {
      const t = lines[i].trim();
      if (
        !t ||
        /^---+$/.test(t) ||
        t.startsWith('```') ||
        t.startsWith('>') ||
        /^#{1,6}\s+/.test(t) ||
        (t.startsWith('|') && i + 1 < lines.length && isTableSeparatorRow(lines[i + 1])) ||
        /^[-*]\s+/.test(t) ||
        /^\d+\.\s+/.test(t)
      ) {
        break;
      }
      paraLines.push(t);
      i += 1;
    }
    if (paraLines.length > 0) {
      html.push(`<p>${paraLines.map(renderInlineMarkdown).join(' ')}</p>`);
    } else {
      // Fallback advance if an unhandled single-line token stopped the paragraph scanner
      html.push(`<p>${renderInlineMarkdown(trimmed)}</p>`);
      i += 1;
    }
  }

  return html.join('\n');
}

/**
 * Parse a module's `solutions.md` Markdown into per-question solutions and MCQ answers.
 */
export function parseQuizSolutions(rawMarkdown: string): Record<number, ParsedQuestionSolution> {
  const lines = rawMarkdown.replace(/\r\n/g, '\n').split('\n');
  const sections: Array<{ questionNumber: number; title: string; bodyLines: string[] }> = [];
  let current: { questionNumber: number; title: string; bodyLines: string[] } | null = null;

  for (const line of lines) {
    const heading = /^#{2,3}\s+(?:Question|Solution)\s+(\d+)\b[:\s—–-]*(.*)$/i.exec(line.trim());
    if (heading) {
      if (current) sections.push(current);
      current = {
        questionNumber: Number(heading[1]),
        title: heading[2].trim(),
        bodyLines: [],
      };
      continue;
    }
    if (/^##\s+Part\s+[A-Z]\b/i.test(line.trim())) {
      continue;
    }
    if (current) {
      current.bodyLines.push(line);
    }
  }
  if (current) sections.push(current);

  const result: Record<number, ParsedQuestionSolution> = {};
  for (const sec of sections) {
    // Strip trailing horizontal dividers inside section slice
    const cleanedLines = [...sec.bodyLines];
    while (cleanedLines.length > 0 && (!cleanedLines[cleanedLines.length - 1].trim() || /^---+$/.test(cleanedLines[cleanedLines.length - 1].trim()))) {
      cleanedLines.pop();
    }

    let correctOption: McqOptionLetter | undefined;
    let answerLine: string | undefined;
    const bodyWithoutAnswerHeader: string[] = [];

    for (const ln of cleanedLines) {
      const ansMatch = /^\*\*Correct Answer:\*\*\s*\*\*([A-D])\*\*(.*)$/i.exec(ln.trim());
      if (ansMatch && !correctOption) {
        correctOption = ansMatch[1].toUpperCase() as McqOptionLetter;
        answerLine = `${correctOption}${ansMatch[2].trim() ? ` ${ansMatch[2].trim()}` : ''}`;
        continue;
      }
      bodyWithoutAnswerHeader.push(ln);
    }

    const bodyMd = bodyWithoutAnswerHeader.join('\n').replace(/^\s*\*\*Explanation:\*\*\s*/i, '### Explanation\n\n');
    result[sec.questionNumber] = {
      questionNumber: sec.questionNumber,
      title: sec.title,
      correctOption,
      answerLine,
      explanationHtml: renderSolutionMarkdownToHtml(bodyMd),
    };
  }

  return result;
}

/**
 * Look up parsed quiz solutions for the active VitePress route path.
 */
export function getQuizSolutionsForRoute(
  routePath: string,
): Record<number, ParsedQuestionSolution> | null {
  const normalized = routePath.replace(/\.html$/i, '').replace(/\/$/, '');
  const matched = SOLUTIONS_BY_TRACK.find((entry) => normalized.endsWith(entry.match));
  return matched ? parseQuizSolutions(matched.raw) : null;
}
