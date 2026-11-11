import type { HandbookModuleMeta } from './modules';

export type ReviewRating = 1 | 2 | 3 | 4; // 1 Again | 2 Hard | 3 Good | 4 Easy
export type SolveOutcome = 'solo_pass' | 'guided_review';
export type CardKind = 'cloze' | 'trap' | 'query' | 'checkpoint' | 'dialect';
export type StrengthStatus = 'Strong' | 'Fading' | 'Due' | 'New';

export interface RecallCard {
  id: string;
  moduleId: string;
  kind: CardKind;
  stabilityDays: number;
  difficulty: number;
  lastReviewedAt: string;
  nextDueAt: string;
  lapses: number;
  reps: number;
  lastOutcome: SolveOutcome;
}

export interface RetentionState {
  version: 1;
  xp: number;
  streakDays: number;
  freezesLeft: number;
  lastActiveDate: string | null;
  diagnosticCompleted: boolean;
  cards: Record<string, RecallCard>;
}

export interface ModuleSummary {
  moduleId: string;
  title: string;
  enrolledCount: number;
  strength: number;
  status: StrengthStatus;
  dueCount: number;
}

export interface ReviewSubmission {
  cardId: string;
  moduleId: string;
  kind: CardKind;
  rating: ReviewRating;
  outcome?: SolveOutcome;
  baseXp?: number;
}

export interface ReviewResult {
  card: RecallCard;
  xpAwarded: number;
  intervalDays: number;
}

export interface PlacementAnswerInput {
  cardId: string;
  moduleId: string;
  correct: boolean;
}

export interface PlacementSummary {
  correctCount: number;
  totalCount: number;
  xpAwarded: number;
}

export type ImportResult =
  | { ok: true; cardCount: number }
  | { ok: false; error: string };

export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export interface RetentionStoreOptions {
  storageKey?: string;
  now?: () => Date;
}

export interface RetentionStore {
  getState(): RetentionState;
  getCard(cardId: string): RecallCard | undefined;
  getDueCards(now?: Date): RecallCard[];
  getModuleSummaries(modules: readonly Pick<HandbookModuleMeta, 'moduleId' | 'title'>[], now?: Date): ModuleSummary[];
  submitReview(input: ReviewSubmission, now?: Date): ReviewResult;
  applyPlacementDiagnostic(answers: readonly PlacementAnswerInput[], now?: Date): PlacementSummary;
  exportStateJson(): string;
  importStateJson(rawJson: string): ImportResult;
  resetState(): void;
  subscribe(listener: () => void): () => void;
}

export const DEFAULT_STORAGE_KEY = 'de_sql_handbook_retention_v1';

const DAY_MS = 86_400_000;
const MINUTE_MS = 60_000;
const MAX_FREEZES = 2;
const MAX_INTERVAL_DAYS = 3650;
const INITIAL_INTERVALS_DAYS: Record<Exclude<ReviewRating, 1>, number> = {
  2: 1,
  3: 4,
  4: 9,
};
const GROWTH_FACTORS: Record<Exclude<ReviewRating, 1>, number> = {
  2: 1.2,
  3: 2.25,
  4: 3.0,
};
const VALID_KINDS: ReadonlySet<string> = new Set(['cloze', 'trap', 'query', 'checkpoint', 'dialect']);
const VALID_OUTCOMES: ReadonlySet<string> = new Set(['solo_pass', 'guided_review']);

function createEmptyState(): RetentionState {
  return {
    version: 1,
    xp: 0,
    streakDays: 0,
    freezesLeft: 0,
    lastActiveDate: null,
    diagnosticCompleted: false,
    cards: {},
  };
}

function isValidCardRecord(value: unknown): value is RecallCard {
  if (!value || typeof value !== 'object') return false;
  const c = value as Partial<RecallCard>;
  return (
    typeof c.id === 'string' &&
    c.id.length > 0 &&
    typeof c.moduleId === 'string' &&
    c.moduleId.length > 0 &&
    typeof c.kind === 'string' &&
    VALID_KINDS.has(c.kind) &&
    typeof c.stabilityDays === 'number' &&
    Number.isFinite(c.stabilityDays) &&
    c.stabilityDays > 0 &&
    typeof c.difficulty === 'number' &&
    Number.isFinite(c.difficulty) &&
    typeof c.lastReviewedAt === 'string' &&
    !Number.isNaN(Date.parse(c.lastReviewedAt)) &&
    typeof c.nextDueAt === 'string' &&
    !Number.isNaN(Date.parse(c.nextDueAt)) &&
    typeof c.lapses === 'number' &&
    Number.isInteger(c.lapses) &&
    c.lapses >= 0 &&
    typeof c.reps === 'number' &&
    Number.isInteger(c.reps) &&
    c.reps >= 0 &&
    typeof c.lastOutcome === 'string' &&
    VALID_OUTCOMES.has(c.lastOutcome)
  );
}

function parseValidatedState(raw: string): RetentionState | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== 'object') return null;
  const obj = parsed as Partial<RetentionState>;
  if (obj.version !== 1) return null;
  if (typeof obj.xp !== 'number' || !Number.isFinite(obj.xp) || obj.xp < 0) return null;
  if (typeof obj.streakDays !== 'number' || !Number.isInteger(obj.streakDays) || obj.streakDays < 0) return null;
  if (
    typeof obj.freezesLeft !== 'number' ||
    !Number.isInteger(obj.freezesLeft) ||
    obj.freezesLeft < 0 ||
    obj.freezesLeft > MAX_FREEZES
  ) {
    return null;
  }
  if (obj.lastActiveDate !== undefined && obj.lastActiveDate !== null && typeof obj.lastActiveDate !== 'string') {
    return null;
  }
  if (!obj.cards || typeof obj.cards !== 'object' || Array.isArray(obj.cards)) return null;

  const validatedCards: Record<string, RecallCard> = {};
  for (const [key, entry] of Object.entries(obj.cards)) {
    if (!isValidCardRecord(entry) || entry.id !== key) return null;
    validatedCards[key] = entry;
  }

  return {
    version: 1,
    xp: obj.xp,
    streakDays: obj.streakDays,
    freezesLeft: obj.freezesLeft,
    lastActiveDate: obj.lastActiveDate ?? null,
    diagnosticCompleted: Boolean(obj.diagnosticCompleted),
    cards: validatedCards,
  };
}

function loadState(storage: StorageLike, key: string): RetentionState {
  const raw = storage.getItem(key);
  if (!raw) return createEmptyState();
  return parseValidatedState(raw) ?? createEmptyState();
}

function defaultBaseXp(kind: CardKind): number {
  return kind === 'query' || kind === 'checkpoint' ? 40 : 15;
}

function computeCardStrength(card: RecallCard, nowMs: number): number {
  const reviewedMs = Date.parse(card.lastReviewedAt);
  const elapsedDays = Math.max(0, (nowMs - reviewedMs) / DAY_MS);
  const stability = Math.max(0.25, card.stabilityDays);
  const retrievability = Math.exp((-Math.LN2 * elapsedDays) / stability);
  return Math.max(0, Math.min(100, Math.round(100 * retrievability)));
}

function calendarDayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function daysBetweenDayKeys(prevKey: string, nextKey: string): number {
  const prevMs = Date.parse(`${prevKey}T00:00:00.000Z`);
  const nextMs = Date.parse(`${nextKey}T00:00:00.000Z`);
  return Math.round((nextMs - prevMs) / DAY_MS);
}

function advanceConsistencyStreak(
  state: RetentionState,
  now: Date,
): Pick<RetentionState, 'streakDays' | 'freezesLeft' | 'lastActiveDate'> {
  const todayKey = calendarDayKey(now);
  if (!state.lastActiveDate) {
    return { streakDays: 1, freezesLeft: state.freezesLeft, lastActiveDate: todayKey };
  }

  const diffDays = daysBetweenDayKeys(state.lastActiveDate, todayKey);
  if (diffDays <= 0) {
    return {
      streakDays: state.streakDays,
      freezesLeft: state.freezesLeft,
      lastActiveDate: state.lastActiveDate,
    };
  }

  const missedDays = diffDays - 1;
  if (missedDays === 0 || missedDays <= state.freezesLeft) {
    const remainingFreezes = state.freezesLeft - missedDays;
    const nextStreak = state.streakDays + 1;
    const earnedFreeze = nextStreak % 7 === 0 ? 1 : 0;
    return {
      streakDays: nextStreak,
      freezesLeft: Math.min(MAX_FREEZES, remainingFreezes + earnedFreeze),
      lastActiveDate: todayKey,
    };
  }

  return {
    streakDays: 1,
    freezesLeft: 0,
    lastActiveDate: todayKey,
  };
}

export function createMemoryFallbackStorage(): StorageLike {
  const map = new Map<string, string>();
  return {
    getItem: (key) => map.get(key) ?? null,
    setItem: (key, value) => {
      map.set(key, value);
    },
    removeItem: (key) => {
      map.delete(key);
    },
  };
}

export function createRetentionStore(
  storage: StorageLike,
  options: RetentionStoreOptions = {},
): RetentionStore {
  const storageKey = options.storageKey ?? DEFAULT_STORAGE_KEY;
  const clock = options.now ?? (() => new Date());
  const listeners = new Set<() => void>();
  let state = loadState(storage, storageKey);

  function save(): void {
    storage.setItem(storageKey, JSON.stringify(state));
    for (const listener of listeners) listener();
  }

  return {
    getState() {
      return state;
    },

    getCard(cardId) {
      return state.cards[cardId];
    },

    getDueCards(now = clock()) {
      const nowMs = now.getTime();
      return Object.values(state.cards)
        .filter((card) => Date.parse(card.nextDueAt) <= nowMs)
        .sort((a, b) => Date.parse(a.nextDueAt) - Date.parse(b.nextDueAt));
    },

    getModuleSummaries(modules, now = clock()) {
      const nowMs = now.getTime();
      return modules.map((mod) => {
        const cards = Object.values(state.cards).filter((c) => c.moduleId === mod.moduleId);
        if (cards.length === 0) {
          return {
            moduleId: mod.moduleId,
            title: mod.title,
            enrolledCount: 0,
            strength: 0,
            status: 'New',
            dueCount: 0,
          };
        }
        const dueCount = cards.filter((c) => Date.parse(c.nextDueAt) <= nowMs).length;
        const avgStrength = Math.round(
          cards.reduce((acc, card) => acc + computeCardStrength(card, nowMs), 0) / cards.length,
        );
        let status: StrengthStatus = 'Fading';
        if (dueCount > 0 || avgStrength < 50) status = 'Due';
        else if (avgStrength >= 80) status = 'Strong';

        return {
          moduleId: mod.moduleId,
          title: mod.title,
          enrolledCount: cards.length,
          strength: avgStrength,
          status,
          dueCount,
        };
      });
    },

    submitReview(input, now = clock()) {
      const nowMs = now.getTime();
      const prev = state.cards[input.cardId];
      const prevDifficulty = prev?.difficulty ?? 5;
      const prevStability = prev?.stabilityDays ?? 1;
      const prevReps = prev?.reps ?? 0;
      const prevLapses = prev?.lapses ?? 0;

      const outcome: SolveOutcome = input.outcome ?? 'solo_pass';
      const baseXp = input.baseXp ?? defaultBaseXp(input.kind);
      const xpAwarded = outcome === 'solo_pass' ? baseXp : Math.max(1, Math.round(baseXp * 0.2));

      let intervalDays: number;
      let nextDueMs: number;
      let stabilityDays: number;
      let difficulty = prevDifficulty;
      let reps = prevReps;
      let lapses = prevLapses;

      if (outcome === 'guided_review') {
        intervalDays = 1;
        stabilityDays = 1;
        reps = Math.max(1, prevReps);
        nextDueMs = nowMs + DAY_MS;
      } else if (input.rating === 1) {
        lapses += 1;
        reps = 0;
        difficulty = Math.min(10, Number((difficulty + 1.2).toFixed(2)));
        stabilityDays = 0.5;
        intervalDays = 10 / (24 * 60);
        nextDueMs = nowMs + 10 * MINUTE_MS;
      } else {
        reps += 1;
        const delta = input.rating === 2 ? 0.3 : input.rating === 3 ? -0.15 : -0.45;
        difficulty = Math.max(1, Math.min(10, Number((difficulty + delta).toFixed(2))));

        if (prevReps === 0) {
          intervalDays = INITIAL_INTERVALS_DAYS[input.rating];
        } else {
          intervalDays = Math.min(
            MAX_INTERVAL_DAYS,
            Math.max(1, Math.round(prevStability * GROWTH_FACTORS[input.rating])),
          );
        }
        stabilityDays = intervalDays;
        nextDueMs = nowMs + intervalDays * DAY_MS;
      }

      const card: RecallCard = {
        id: input.cardId,
        moduleId: input.moduleId,
        kind: input.kind,
        stabilityDays,
        difficulty,
        lastReviewedAt: new Date(nowMs).toISOString(),
        nextDueAt: new Date(nextDueMs).toISOString(),
        lapses,
        reps,
        lastOutcome: outcome,
      };

      const streakPatch = advanceConsistencyStreak(state, now);
      state = {
        ...state,
        ...streakPatch,
        xp: state.xp + xpAwarded,
        cards: {
          ...state.cards,
          [card.id]: card,
        },
      };
      save();

      return { card, xpAwarded, intervalDays };
    },

    applyPlacementDiagnostic(answers, now = clock()) {
      const nowIso = now.toISOString();
      const nowMs = now.getTime();
      const updatedCards = { ...state.cards };
      let correctCount = 0;

      for (const ans of answers) {
        if (ans.correct) {
          correctCount += 1;
          updatedCards[ans.cardId] = {
            id: ans.cardId,
            moduleId: ans.moduleId,
            kind: 'trap',
            stabilityDays: 9,
            difficulty: 4,
            lastReviewedAt: nowIso,
            nextDueAt: new Date(nowMs + 9 * DAY_MS).toISOString(),
            lapses: 0,
            reps: 1,
            lastOutcome: 'solo_pass',
          };
        } else {
          updatedCards[ans.cardId] = {
            id: ans.cardId,
            moduleId: ans.moduleId,
            kind: 'trap',
            stabilityDays: 1,
            difficulty: 6,
            lastReviewedAt: nowIso,
            nextDueAt: nowIso,
            lapses: 0,
            reps: 0,
            lastOutcome: 'guided_review',
          };
        }
      }

      const xpAwarded = correctCount * 5;
      const streakPatch = correctCount > 0 ? advanceConsistencyStreak(state, now) : {};
      state = {
        ...state,
        ...streakPatch,
        diagnosticCompleted: true,
        xp: state.xp + xpAwarded,
        cards: updatedCards,
      };
      save();

      return {
        correctCount,
        totalCount: answers.length,
        xpAwarded,
      };
    },

    exportStateJson() {
      return JSON.stringify(state, null, 2);
    },

    importStateJson(rawJson) {
      const next = parseValidatedState(rawJson);
      if (!next) {
        return {
          ok: false,
          error: 'Invalid backup file: expected version 1 JSON exported from SQL DE Handbook.',
        };
      }
      state = next;
      save();
      return { ok: true, cardCount: Object.keys(next.cards).length };
    },

    resetState() {
      state = createEmptyState();
      storage.removeItem(storageKey);
      for (const listener of listeners) listener();
    },

    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
  };
}
