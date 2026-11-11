import fs from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { parseQuizSolutions } from './quizCatalog';
import { enhanceQuizDocument } from './quizEnhancer';

describe('Quiz Catalog Parser (single-source solutions.md)', () => {
  it('extracts all MCQ answers and HTML-escaped explanations across exercises 01-05', () => {
    const repoRoot = path.resolve(__dirname, '../..');
    const checks: Array<{ rel: string; expectedCount: number; mcqChecks: Record<number, string> }> = [
      { rel: 'exercises/01-foundations/solutions.md', expectedCount: 10, mcqChecks: { 1: 'C', 2: 'C', 3: 'D', 4: 'B', 5: 'C' } },
      { rel: 'exercises/02-window-functions/solutions.md', expectedCount: 10, mcqChecks: { 1: 'A', 2: 'B', 3: 'C', 4: 'D', 5: 'C' } },
      { rel: 'exercises/03-de-patterns/solutions.md', expectedCount: 12, mcqChecks: { 1: 'B', 3: 'A', 8: 'D', 10: 'B' } },
      { rel: 'exercises/04-cloud-dw/solutions.md', expectedCount: 8, mcqChecks: {} },
      { rel: 'exercises/05-performance/solutions.md', expectedCount: 8, mcqChecks: {} },
    ];

    for (const item of checks) {
      const raw = fs.readFileSync(path.join(repoRoot, item.rel), 'utf8');
      const parsed = parseQuizSolutions(raw);
      expect(Object.keys(parsed)).toHaveLength(item.expectedCount);

      for (const [qNum, letter] of Object.entries(item.mcqChecks)) {
        const entry = parsed[Number(qNum)];
        expect(entry?.correctOption).toBe(letter);
        expect(entry?.explanationHtml.length).toBeGreaterThan(20);
      }
    }
  });
});

describe('Interactive Quiz Enhancer (options + Explanation tab)', () => {
  it('renders Question & Explanation tabs, scores option clicks immediately, and switches tabs cleanly', () => {
    const doc = document.createElement('div');
    doc.innerHTML = `
      <h1 id="mod-1-quiz">Module 1 Quiz</h1>
      <h2 id="part-a">Part A: Multiple Choice</h2>
      <h3 id="question-1">Question 1 — Filtering <a class="header-anchor" href="#question-1">#</a></h3>
      <p>Which query filters aggregated groups correctly?</p>
      <ul>
        <li><p><strong>A.</strong> Wrong WHERE filter</p></li>
        <li><p><strong>B.</strong> Alias in HAVING</p></li>
        <li><p><strong>C.</strong> HAVING AVG(row_count) &gt; 10000</p></li>
        <li><p><strong>D.</strong> ORDER BY boolean</p></li>
      </ul>
      <hr />
      <h2 id="part-b">Part B: Write the Query</h2>
      <h3 id="question-6">Question 6 — Anti-Join</h3>
      <p>Find orphan rows.</p>
    `;

    const solutions = parseQuizSolutions(`
### Question 1 — Filtering
**Correct Answer:** **C**

**Explanation:**
- **C is correct** because \`HAVING\` runs after \`GROUP BY\`.

### Question 6 — Anti-Join
**Solution:**
\`\`\`sql
SELECT * FROM a WHERE NOT EXISTS (SELECT 1 FROM b WHERE b.id = a.id);
\`\`\`
    `);

    enhanceQuizDocument(doc, solutions);

    // Check headings retain ids for Right-Side Section Mini-Map
    expect(doc.querySelector('[id="question-1"]')?.tagName).toBe('H3');

    // Check accessible two-tab structure
    const q1Card = doc.querySelector('.de-quiz-card[data-question="1"]')!;
    const tabs = Array.from(q1Card.querySelectorAll<HTMLButtonElement>('[role="tab"]'));
    expect(tabs.map((t) => t.textContent?.trim())).toEqual(['Question', 'Explanation']);
    expect(tabs[0].getAttribute('aria-selected')).toBe('true');
    expect(tabs[1].getAttribute('aria-selected')).toBe('false');

    const panels = Array.from(q1Card.querySelectorAll<HTMLElement>('[role="tabpanel"]'));
    expect(panels[0].hasAttribute('hidden')).toBe(false);
    expect(panels[1].getAttribute('hidden')).toBe('until-found');

    // Click wrong option A -> immediate wrong/correct feedback & score update
    const optA = q1Card.querySelector<HTMLButtonElement>('button.de-quiz-option[data-option="A"]')!;
    const optC = q1Card.querySelector<HTMLButtonElement>('button.de-quiz-option[data-option="C"]')!;
    optA.click();

    expect(optA.dataset.state).toBe('wrong');
    expect(optC.dataset.state).toBe('correct');
    const feedback = q1Card.querySelector<HTMLElement>('.de-quiz-feedback')!;
    expect(feedback.hidden).toBe(false);
    expect(feedback.textContent).toContain('Incorrect');
    expect(feedback.textContent).toContain('C');

    // Switch to Explanation tab via click
    tabs[1].click();
    expect(tabs[0].getAttribute('aria-selected')).toBe('false');
    expect(tabs[1].getAttribute('aria-selected')).toBe('true');
    expect(panels[0].getAttribute('hidden')).toBe('until-found');
    expect(panels[1].hasAttribute('hidden')).toBe(false);
    expect(panels[1].textContent).toContain('HAVING runs after GROUP BY');

    // Switch back with ArrowLeft keyboard shortcut per tabs guide
    tabs[1].dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }));
    expect(tabs[0].getAttribute('aria-selected')).toBe('true');
    expect(panels[0].hasAttribute('hidden')).toBe(false);

    // Open-ended Question 6 gets Solution & Explanation tab too
    const q6Tabs = Array.from(
      doc.querySelectorAll<HTMLButtonElement>('.de-quiz-card[data-question="6"] [role="tab"]'),
    );
    expect(q6Tabs[1].textContent?.trim()).toBe('Solution & Explanation');
    q6Tabs[1].click();
    expect(doc.querySelector('.de-quiz-card[data-question="6"] [data-quiz-explanation]')?.textContent).toContain(
      'SELECT * FROM a',
    );
  });
});
