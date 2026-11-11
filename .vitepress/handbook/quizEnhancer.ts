import type { McqOptionLetter, ParsedQuestionSolution } from './quizCatalog';

interface QuizQuestionState {
  answeredCorrectly?: boolean;
  selectedOption?: McqOptionLetter;
  correctOption?: McqOptionLetter;
}

function getQuestionHeadingNumber(heading: Element): number | null {
  const match = /^Question\s+(\d+)\b/i.exec((heading.textContent ?? '').trim());
  return match ? Number(match[1]) : null;
}

function isNextSectionBoundary(node: Element): boolean {
  const tag = node.tagName.toUpperCase();
  if (tag === 'HR') return true;
  if (tag === 'H2' || tag === 'H3') {
    const txt = (node.textContent ?? '').trim();
    return /^Question\s+\d+\b/i.test(txt) || /^Part\s+[A-Z]\b/i.test(txt);
  }
  return false;
}

function extractOptionLetter(li: HTMLLIElement): McqOptionLetter | null {
  const txt = (li.textContent ?? '').trim();
  const match = /^([A-D])\.\s*/.exec(txt);
  return match ? (match[1] as McqOptionLetter) : null;
}

function findMcqOptionList(nodes: Node[]): {
  listEl: HTMLUListElement;
  items: Array<{ letter: McqOptionLetter; li: HTMLLIElement }>;
} | null {
  for (let idx = nodes.length - 1; idx >= 0; idx -= 1) {
    const node = nodes[idx];
    if (node instanceof HTMLUListElement) {
      const liList = Array.from(node.children).filter(
        (child): child is HTMLLIElement => child instanceof HTMLLIElement,
      );
      if (liList.length < 2) continue;
      const mapped = liList
        .map((li) => ({ letter: extractOptionLetter(li), li }))
        .filter((item): item is { letter: McqOptionLetter; li: HTMLLIElement } => item.letter !== null);
      if (mapped.length === liList.length && mapped.some((m) => m.letter === 'A')) {
        return { listEl: node, items: mapped };
      }
    }
  }
  return null;
}

function stripLeadingOptionPrefix(li: HTMLLIElement, letter: McqOptionLetter): void {
  const firstChild = li.firstElementChild;
  const strong =
    firstChild?.tagName === 'P'
      ? firstChild.querySelector('strong')
      : Array.from(li.children).find((el) => el.tagName.toUpperCase() === 'STRONG') ?? null;

  if (strong && new RegExp(`^${letter}\\.?$`).test((strong.textContent ?? '').trim())) {
    const nextSibling = strong.nextSibling;
    if (nextSibling && nextSibling.nodeType === Node.TEXT_NODE) {
      nextSibling.textContent = (nextSibling.textContent ?? '').replace(/^\s+/, '');
    }
    strong.remove();
  }
}

function createElement<K extends keyof HTMLElementTagNameMap>(
  doc: Document,
  tag: K,
  className?: string,
  text?: string,
): HTMLElementTagNameMap[K] {
  const el = doc.createElement(tag);
  if (className) el.className = className;
  if (text !== undefined) el.textContent = text;
  return el;
}

/**
 * Transform rendered quiz Markdown DOM inside `docRoot` into interactive option
 * cards with instant Right/Wrong feedback and an Explanation tab backed by `solutions`.
 */
export function enhanceQuizDocument(
  docRoot: Element | null,
  solutions: Record<number, ParsedQuestionSolution>,
): void {
  if (!docRoot || (docRoot as HTMLElement).dataset.deQuizEnhanced === 'true') {
    return;
  }

  const doc = docRoot.ownerDocument;
  const headings = Array.from(docRoot.querySelectorAll('h2, h3')).filter(
    (h) => getQuestionHeadingNumber(h) !== null,
  );
  if (headings.length === 0) return;

  const states = new Map<number, QuizQuestionState>();
  const summaryBar = createElement(doc, 'div', 'de-quiz-summary');
  summaryBar.setAttribute('role', 'status');
  summaryBar.setAttribute('aria-live', 'polite');
  summaryBar.dataset.testid = 'quiz-summary';

  const summaryText = createElement(doc, 'span', 'de-num');
  summaryBar.append(summaryText);

  const resetCallbacks: Array<() => void> = [];
  const resetAllBtn = createElement(doc, 'button', 'de-btn de-btn-subtle', 'Reset Quiz');
  resetAllBtn.type = 'button';
  resetAllBtn.hidden = true;
  resetAllBtn.addEventListener('click', () => {
    for (const resetFn of resetCallbacks) resetFn();
    updateSummary();
  });
  summaryBar.append(resetAllBtn);

  function updateSummary() {
    const mcqTotal = Array.from(states.values()).filter((s) => Boolean(s.correctOption)).length;
    if (mcqTotal === 0) {
      summaryText.textContent = `${headings.length} practice challenges · Use the Solution & Explanation tab on each card`;
      resetAllBtn.hidden = true;
      return;
    }
    const answered = Array.from(states.values()).filter((s) => s.selectedOption !== undefined);
    const correctCount = answered.filter((s) => s.answeredCorrectly).length;
    summaryText.textContent = `MCQ Score: ${correctCount} / ${mcqTotal} · Answered: ${answered.length} / ${mcqTotal}`;
    resetAllBtn.hidden = answered.length === 0;
  }

  headings[0].parentElement?.insertBefore(summaryBar, headings[0]);

  for (const heading of headings) {
    const qNum = getQuestionHeadingNumber(heading);
    if (qNum === null) continue;
    const solution = solutions[qNum];

    // Gather nodes belonging to this question before modifying DOM
    const contentNodes: Node[] = [];
    let cursor: ChildNode | null = heading.nextSibling;
    while (cursor) {
      const next = cursor.nextSibling;
      if (cursor instanceof Element && isNextSectionBoundary(cursor)) {
        break;
      }
      contentNodes.push(cursor);
      cursor = next;
    }

    const card = createElement(doc, 'section', 'de-quiz-card');
    card.dataset.question = String(qNum);
    if (heading.id) {
      card.setAttribute('aria-labelledby', heading.id);
    }

    const cardTop = createElement(doc, 'div', 'de-quiz-card-head');
    const statusBadge = createElement(
      doc,
      'span',
      'de-badge de-quiz-status',
      solution?.correctOption ? 'Select option' : 'SQL Challenge',
    );
    statusBadge.dataset.status = solution?.correctOption ? 'pending' : 'open';

    heading.parentElement?.insertBefore(card, heading);
    cardTop.append(heading, statusBadge);
    card.append(cardTop);

    // Accessible tablist per `tabs` guide (selection follows focus + Arrow keys fallback)
    const tabList = createElement(doc, 'div', 'de-quiz-tablist');
    tabList.setAttribute('role', 'tablist');
    tabList.setAttribute('focusgroup', 'tablist nomemory');
    tabList.setAttribute('aria-label', `Question ${qNum} tabs`);

    const qTabId = `de-quiz-q-${qNum}-tab`;
    const expTabId = `de-quiz-exp-${qNum}-tab`;

    const qTab = createElement(doc, 'button', 'de-quiz-tab', 'Question');
    qTab.type = 'button';
    qTab.id = qTabId;
    qTab.setAttribute('role', 'tab');
    qTab.setAttribute('aria-selected', 'true');
    qTab.setAttribute('focusgroupstart', '');

    const expTab = createElement(
      doc,
      'button',
      'de-quiz-tab',
      solution?.correctOption ? 'Explanation' : 'Solution & Explanation',
    );
    expTab.type = 'button';
    expTab.id = expTabId;
    expTab.setAttribute('role', 'tab');
    expTab.setAttribute('aria-selected', 'false');
    expTab.tabIndex = -1;

    tabList.append(qTab, expTab);
    card.append(tabList);

    const qPanel = createElement(doc, 'div', 'de-quiz-panel');
    qPanel.setAttribute('role', 'tabpanel');
    qPanel.setAttribute('aria-labelledby', qTabId);
    qPanel.tabIndex = 0;
    const qBody = createElement(doc, 'div', 'de-quiz-panel-body');
    qPanel.append(qBody);

    const expPanel = createElement(doc, 'div', 'de-quiz-panel');
    expPanel.setAttribute('role', 'tabpanel');
    expPanel.setAttribute('aria-labelledby', expTabId);
    expPanel.setAttribute('hidden', 'until-found');
    expPanel.dataset.quizExplanation = 'true';
    const expBody = createElement(doc, 'div', 'de-quiz-panel-body');
    expPanel.append(expBody);

    card.append(qPanel, expPanel);

    function activateTab(which: 'question' | 'explanation', shouldFocus = false) {
      const showQuestion = which === 'question';
      qTab.setAttribute('aria-selected', String(showQuestion));
      expTab.setAttribute('aria-selected', String(!showQuestion));
      qTab.tabIndex = showQuestion ? 0 : -1;
      expTab.tabIndex = showQuestion ? -1 : 0;
      qTab.toggleAttribute('focusgroupstart', showQuestion);
      expTab.toggleAttribute('focusgroupstart', !showQuestion);

      if (showQuestion) {
        qPanel.removeAttribute('hidden');
        qPanel.tabIndex = 0;
        expPanel.setAttribute('hidden', 'until-found');
        expPanel.removeAttribute('tabindex');
        if (shouldFocus) qTab.focus();
      } else {
        expPanel.removeAttribute('hidden');
        expPanel.tabIndex = 0;
        qPanel.setAttribute('hidden', 'until-found');
        qPanel.removeAttribute('tabindex');
        if (shouldFocus) expTab.focus();
      }
    }

    qTab.addEventListener('click', () => activateTab('question'));
    expTab.addEventListener('click', () => activateTab('explanation'));

    // Fallback arrow/Home/End navigation when native focusgroup is unsupported
    tabList.addEventListener('keydown', (event) => {
      if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') {
        event.preventDefault();
        const currentlyQuestion = qTab.getAttribute('aria-selected') === 'true';
        activateTab(currentlyQuestion ? 'explanation' : 'question', true);
      } else if (event.key === 'Home') {
        event.preventDefault();
        activateTab('question', true);
      } else if (event.key === 'End') {
        event.preventDefault();
        activateTab('explanation', true);
      }
    });

    // Keep tab state synced when browser Find-in-Page matches hidden panel content
    qPanel.addEventListener('beforematch', () => activateTab('question'));
    expPanel.addEventListener('beforematch', () => activateTab('explanation'));

    // Populate Question panel and wire interactive MCQ options if applicable
    const mcqMatch = solution?.correctOption ? findMcqOptionList(contentNodes) : null;
    for (const node of contentNodes) {
      if (mcqMatch && node === mcqMatch.listEl) continue;
      qBody.append(node);
    }

    if (mcqMatch && solution?.correctOption) {
      const correctLetter = solution.correctOption;
      states.set(qNum, { correctOption: correctLetter });

      const optionsGroup = createElement(doc, 'div', 'de-quiz-options');
      optionsGroup.setAttribute('role', 'group');
      optionsGroup.setAttribute('aria-label', `Options for Question ${qNum}`);

      const optionButtons: HTMLButtonElement[] = [];
      const feedbackBox = createElement(doc, 'div', 'de-quiz-feedback');
      feedbackBox.setAttribute('role', 'status');
      feedbackBox.setAttribute('aria-live', 'polite');
      feedbackBox.hidden = true;

      for (const item of mcqMatch.items) {
        stripLeadingOptionPrefix(item.li, item.letter);

        const optBtn = createElement(doc, 'button', 'de-quiz-option');
        optBtn.type = 'button';
        optBtn.dataset.option = item.letter;
        optBtn.setAttribute('aria-pressed', 'false');

        const keyBadge = createElement(doc, 'span', 'de-quiz-opt-key de-num', item.letter);
        const contentSpan = createElement(doc, 'span', 'de-quiz-opt-content');
        while (item.li.firstChild) {
          contentSpan.append(item.li.firstChild);
        }
        const verdictSpan = createElement(doc, 'span', 'de-quiz-opt-verdict');
        verdictSpan.setAttribute('aria-hidden', 'true');

        optBtn.append(keyBadge, contentSpan, verdictSpan);
        optionButtons.push(optBtn);
        optionsGroup.append(optBtn);

        optBtn.addEventListener('click', () => {
          const isCorrect = item.letter === correctLetter;
          states.set(qNum, {
            correctOption: correctLetter,
            selectedOption: item.letter,
            answeredCorrectly: isCorrect,
          });

          for (const btn of optionButtons) {
            const btnLetter = btn.dataset.option;
            const verdictEl = btn.querySelector<HTMLElement>('.de-quiz-opt-verdict');
            btn.setAttribute('aria-pressed', String(btnLetter === item.letter));
            if (btnLetter === correctLetter) {
              btn.dataset.state = 'correct';
              if (verdictEl) verdictEl.textContent = '✓ Correct';
            } else if (btnLetter === item.letter) {
              btn.dataset.state = 'wrong';
              if (verdictEl) verdictEl.textContent = '✕ Your choice';
            } else {
              delete btn.dataset.state;
              if (verdictEl) verdictEl.textContent = '';
            }
          }

          statusBadge.textContent = isCorrect ? '✓ Right' : `✕ Wrong · Answer: ${correctLetter}`;
          statusBadge.dataset.status = isCorrect ? 'mastered' : 'due';

          feedbackBox.replaceChildren();
          feedbackBox.hidden = false;
          feedbackBox.dataset.state = isCorrect ? 'correct' : 'wrong';

          const msg = createElement(
            doc,
            'span',
            '',
            isCorrect
              ? `✓ Correct! Option ${correctLetter} is right.`
              : `✕ Incorrect — you selected ${item.letter}. Correct answer is ${correctLetter}.`,
          );
          const openExpBtn = createElement(doc, 'button', 'de-btn de-btn-subtle', 'Open Explanation tab →');
          openExpBtn.type = 'button';
          openExpBtn.addEventListener('click', () => activateTab('explanation', true));
          feedbackBox.append(msg, openExpBtn);

          updateSummary();
        });
      }

      mcqMatch.listEl.remove();
      qBody.append(optionsGroup, feedbackBox);

      resetCallbacks.push(() => {
        states.set(qNum, { correctOption: correctLetter });
        statusBadge.textContent = 'Select option';
        statusBadge.dataset.status = 'pending';
        feedbackBox.hidden = true;
        feedbackBox.replaceChildren();
        for (const btn of optionButtons) {
          delete btn.dataset.state;
          btn.setAttribute('aria-pressed', 'false');
          const verdictEl = btn.querySelector<HTMLElement>('.de-quiz-opt-verdict');
          if (verdictEl) verdictEl.textContent = '';
        }
        activateTab('question');
      });
    } else {
      states.set(qNum, {});
    }

    // Populate Explanation tab panel from solutions.md
    if (solution) {
      if (solution.answerLine) {
        const answerBanner = createElement(doc, 'div', 'de-quiz-answer-banner');
        const label = createElement(doc, 'strong', '', 'Correct Answer: ');
        const val = createElement(doc, 'span', '', solution.answerLine);
        answerBanner.append(label, val);
        expBody.append(answerBanner);
      }
      const expContent = createElement(doc, 'div', 'de-quiz-exp-content');
      expContent.innerHTML = solution.explanationHtml;
      const backBtn = createElement(doc, 'button', 'de-btn de-btn-subtle de-quiz-back-btn', '← Back to Question');
      backBtn.type = 'button';
      backBtn.addEventListener('click', () => activateTab('question', true));
      expBody.append(expContent, backBtn);
    } else {
      expBody.append(
        createElement(doc, 'p', '', 'No explanation entry found for this question in solutions.md.'),
      );
    }
  }

  updateSummary();
  (docRoot as HTMLElement).dataset.deQuizEnhanced = 'true';
}
