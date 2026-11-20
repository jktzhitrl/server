// TypeScript-Port der Spielregeln aus lib/core (Dart). Gleiche Semantik:
// Die Paritätstests in test/engine.test.ts prüfen den Port gegen Testvektoren,
// die aus der Dart-Implementierung erzeugt werden (tool/gen_vectors.dart).

export type OutMode = 'single' | 'double' | 'master';
export type InMode = 'straight' | 'double' | 'master';

export interface Rules {
  startScore: number;
  inMode: InMode;
  outMode: OutMode;
  format: { legsToWinSet: number; setsToWin: number };
  starterRule: 'alternating' | 'fixed';
  bullOffForDecider?: boolean;
}

/** Dart als Code `multiplier * 100 + number` (Miss = 0). */
export interface Dart { m: number; n: number }

export function decodeDart(code: number): Dart {
  if (!Number.isInteger(code) || code < 0) throw new Error(`Ungültiger Dart: ${code}`);
  const m = Math.floor(code / 100);
  const n = code % 100;
  if (m === 0) {
    if (n !== 0) throw new Error(`Ungültiger Dart: ${code}`);
    return { m: 0, n: 0 };
  }
  if (m < 1 || m > 3) throw new Error(`Ungültiger Dart: ${code}`);
  if (n === 25) {
    if (m === 3) throw new Error('Es gibt kein Triple-Bull');
    return { m, n };
  }
  if (n < 1 || n > 20) throw new Error(`Ungültiger Dart: ${code}`);
  return { m, n };
}

export const score = (d: Dart) => d.m * d.n;

const ALL_SCORING: Dart[] = (() => {
  const out: Dart[] = [];
  for (let n = 1; n <= 20; n++) out.push({ m: 1, n }, { m: 2, n }, { m: 3, n });
  out.push({ m: 1, n: 25 }, { m: 2, n: 25 });
  return out;
})();

export function isValidFinishDart(d: Dart, out: OutMode): boolean {
  if (d.m === 0) return false;
  if (out === 'single') return true;
  if (out === 'double') return d.m === 2;
  return d.m === 2 || d.m === 3;
}

export function opensLeg(d: Dart, inMode: InMode): boolean {
  if (d.m === 0) return false;
  if (inMode === 'straight') return true;
  if (inMode === 'double') return d.m === 2;
  return d.m === 2 || d.m === 3;
}

export const minimumRemaining = (out: OutMode) => (out === 'single' ? 1 : 2);

export function isOneDartFinish(s: number, out: OutMode): boolean {
  return ALL_SCORING.some((d) => score(d) === s && isValidFinishDart(d, out));
}

const finishCache = new Map<number, boolean>();
export function canFinishWithDarts(s: number, darts: number, out: OutMode): boolean {
  if (darts < 1 || darts > 3 || s < 1) return false;
  const key = (s * 4 + darts) * 4 + ['single', 'double', 'master'].indexOf(out);
  const hit = finishCache.get(key);
  if (hit !== undefined) return hit;
  let res: boolean;
  if (darts === 1) {
    res = isOneDartFinish(s, out);
  } else {
    const min = minimumRemaining(out);
    res = (s >= min && canFinishWithDarts(s, darts - 1, out)) ||
      ALL_SCORING.some((d) => s - score(d) >= min && canFinishWithDarts(s - score(d), darts - 1, out));
  }
  finishCache.set(key, res);
  return res;
}

const reachCache = new Map<number, boolean>();
export function isReachableTotal(total: number, darts: number): boolean {
  if (total < 0 || darts < 1 || darts > 3) return false;
  const key = total * 4 + darts;
  const hit = reachCache.get(key);
  if (hit !== undefined) return hit;
  let res: boolean;
  if (darts === 1) {
    res = total === 0 || ALL_SCORING.some((d) => score(d) === total);
  } else {
    res = isReachableTotal(total, darts - 1) ||
      ALL_SCORING.some((d) => total - score(d) >= 0 && isReachableTotal(total - score(d), darts - 1));
  }
  reachCache.set(key, res);
  return res;
}

export type Outcome = 'normal' | 'bust' | 'checkout';
export interface Evaluation {
  outcome: Outcome;
  scoreBefore: number;
  scoreAfter: number;
  points: number;
  enteredTotal: number;
  dartsCounted: number;
  openedAfter: boolean;
}

export function evaluateDarts(
  remaining: number, opened: boolean, darts: Dart[], rules: Pick<Rules, 'inMode' | 'outMode'>,
  allowIncomplete = false,
): Evaluation {
  if (darts.length === 0) throw new Error('Keine Darts übergeben');
  if (darts.length > 3) throw new Error('Maximal 3 Darts pro Aufnahme');
  let cur = remaining;
  let open = opened || rules.inMode === 'straight';
  let sum = 0;
  const min = minimumRemaining(rules.outMode);
  const bust = (): Evaluation => ({
    outcome: 'bust', scoreBefore: remaining, scoreAfter: remaining, points: 0,
    enteredTotal: sum, dartsCounted: 3, openedAfter: opened,
  });
  const ensureEnd = (isLast: boolean, what: string) => {
    if (!isLast) throw new Error(`Nach ${what} dürfen keine weiteren Darts folgen`);
  };
  for (let i = 0; i < darts.length; i++) {
    const d = darts[i];
    if (!open) {
      if (opensLeg(d, rules.inMode)) open = true; else continue;
    }
    sum += score(d);
    const next = cur - score(d);
    const isLast = i === darts.length - 1;
    if (next === 0) {
      if (!isValidFinishDart(d, rules.outMode)) { ensureEnd(isLast, 'Bust'); return bust(); }
      ensureEnd(isLast, 'Checkout');
      return {
        outcome: 'checkout', scoreBefore: remaining, scoreAfter: 0, points: remaining,
        enteredTotal: sum, dartsCounted: i + 1, openedAfter: true,
      };
    }
    if (next < min) { ensureEnd(isLast, 'Bust'); return bust(); }
    cur = next;
  }
  if (darts.length !== 3 && !allowIncomplete) {
    throw new Error(`Aufnahme unvollständig: ${darts.length} von 3 Darts`);
  }
  return {
    outcome: 'normal', scoreBefore: remaining, scoreAfter: cur, points: remaining - cur,
    enteredTotal: sum, dartsCounted: darts.length, openedAfter: open,
  };
}

export function evaluateTotal(
  remaining: number, opened: boolean, total: number, rules: Pick<Rules, 'inMode' | 'outMode'>,
  dartsUsed?: number | null, forceBust = false,
): Evaluation {
  if (!Number.isInteger(total) || total < 0 || total > 180) throw new Error('Summe muss 0..180 sein');
  const used = dartsUsed ?? 3;
  if (!Number.isInteger(used) || used < 1 || used > 3) throw new Error('dartsUsed muss 1..3 sein');
  const bust = (): Evaluation => ({
    outcome: 'bust', scoreBefore: remaining, scoreAfter: remaining, points: 0,
    enteredTotal: total, dartsCounted: 3, openedAfter: opened,
  });
  if (forceBust) return bust();
  if (!isReachableTotal(total, 3)) throw new Error(`${total} ist mit 3 Darts nicht erreichbar`);
  if (!isReachableTotal(total, used)) throw new Error(`${total} ist mit ${used} Dart(s) nicht erreichbar`);
  const next = remaining - total;
  if (next < 0) return bust();
  if (next === 0) {
    if (!canFinishWithDarts(remaining, used, rules.outMode)) {
      throw new Error(`Checkout von ${remaining} mit ${used} Dart(s) nicht möglich`);
    }
    return {
      outcome: 'checkout', scoreBefore: remaining, scoreAfter: 0, points: remaining,
      enteredTotal: total, dartsCounted: used, openedAfter: true,
    };
  }
  if (next < minimumRemaining(rules.outMode)) return bust();
  return {
    outcome: 'normal', scoreBefore: remaining, scoreAfter: next, points: total,
    enteredTotal: total, dartsCounted: 3,
    openedAfter: opened || total > 0 || rules.inMode === 'straight',
  };
}

export function countCheckoutAttempts(
  startScore: number, darts: Dart[], rules: Pick<Rules, 'inMode' | 'outMode'>, opened: boolean,
): number {
  let cur = startScore;
  let open = opened || rules.inMode === 'straight';
  let attempts = 0;
  for (const d of darts) {
    if (!open) { if (opensLeg(d, rules.inMode)) open = true; else continue; }
    if (isOneDartFinish(cur, rules.outMode)) attempts++;
    const next = cur - score(d);
    if (next <= 0 || next < minimumRemaining(rules.outMode)) break;
    cur = next;
  }
  return attempts;
}

// ---------------------------------------------------------------- Match-Replay

export interface VisitJson {
  id: string; playerIndex: number; legNo: number; visitNo: number;
  startScore: number; scoreAfter: number; enteredTotal: number; points: number;
  bust: boolean; checkout: boolean; darts: number[] | null; dartsThrown: number;
  checkoutAttempts: number | null; mode: 'perDart' | 'total'; timestamp: string;
}

export interface X01Json {
  rules: Rules;
  playerIds: string[];
  firstStarter?: number;
  starterOverrides?: Record<string, number>;
  visits: VisitJson[];
}

export interface MatchState {
  legNo: number; setNo: number; remaining: number[]; opened: boolean[];
  legsWon: number[]; setsWon: number[]; currentPlayer: number;
  visitsInLeg: number[]; winnerIndex: number | null;
}

export function starterForLeg(m: X01Json, legNo: number): number {
  const o = m.starterOverrides?.[String(legNo)];
  if (o !== undefined) return o;
  const first = m.firstStarter ?? 0;
  if (m.rules.starterRule === 'fixed') return first;
  return (first + legNo - 1) % m.playerIds.length;
}

/** Berechnet den Spielstand aus dem Visit-Log und prüft dessen Konsistenz. */
export function replay(m: X01Json): MatchState {
  const n = m.playerIds.length;
  const r = m.rules;
  let legNo = 1; let setNo = 1;
  let remaining = Array<number>(n).fill(r.startScore);
  let opened = Array<boolean>(n).fill(r.inMode === 'straight');
  let legsWon = Array<number>(n).fill(0);
  const setsWon = Array<number>(n).fill(0);
  let visitsInLeg = Array<number>(n).fill(0);
  let current = starterForLeg(m, 1);
  let winner: number | null = null;
  for (const v of m.visits) {
    if (winner !== null) throw new Error('Aufnahme nach Matchende im Log');
    if (v.playerIndex !== current || v.legNo !== legNo || v.startScore !== remaining[current]) {
      throw new Error(`Inkonsistentes Visit-Log bei ${v.id}`);
    }
    visitsInLeg[current]++;
    if (v.checkout) {
      legsWon[current]++;
      if (legsWon[current] >= r.format.legsToWinSet) {
        setsWon[current]++;
        legsWon = Array<number>(n).fill(0);
        setNo++;
        if (setsWon[current] >= r.format.setsToWin) {
          winner = current;
          remaining[current] = 0;
          break;
        }
      }
      legNo++;
      remaining = Array<number>(n).fill(r.startScore);
      opened = Array<boolean>(n).fill(r.inMode === 'straight');
      visitsInLeg = Array<number>(n).fill(0);
      current = starterForLeg(m, legNo);
    } else {
      remaining[current] = v.scoreAfter;
      if (!v.bust && r.inMode !== 'straight' && v.points > 0) opened[current] = true;
      current = (current + 1) % n;
    }
  }
  return { legNo, setNo: winner !== null ? setNo - 1 : setNo, remaining, opened, legsWon, setsWon, currentPlayer: current, visitsInLeg, winnerIndex: winner };
}

export type VisitInput =
  | { kind: 'darts'; darts: number[] }
  | { kind: 'total'; total: number; dartsUsed?: number | null; checkoutAttempts?: number | null; bust?: boolean };

/** Prüft die Eingabe gegen die Regeln und gibt die neue Aufnahme zurück (nie vom Client vorgegeben). */
export function buildVisit(m: X01Json, input: VisitInput, id: string, now: Date): VisitJson {
  const s = replay(m);
  if (s.winnerIndex !== null) throw new Error('Das Match ist bereits beendet');
  const p = s.currentPlayer;
  let ev: Evaluation;
  let darts: number[] | null = null;
  let attempts: number | null = null;
  if (input.kind === 'darts') {
    const ds = input.darts.map(decodeDart);
    ev = evaluateDarts(s.remaining[p], s.opened[p], ds, m.rules);
    attempts = countCheckoutAttempts(s.remaining[p], ds, m.rules, s.opened[p]);
    darts = input.darts;
  } else {
    ev = evaluateTotal(s.remaining[p], s.opened[p], input.total, m.rules, input.dartsUsed, input.bust ?? false);
    attempts = input.checkoutAttempts ?? null;
    if (attempts !== null && (!Number.isInteger(attempts) || attempts < 0 || attempts > 3)) {
      throw new Error('checkoutAttempts muss 0..3 sein');
    }
    if (ev.outcome === 'checkout' && attempts !== null && attempts < 1) attempts = 1;
  }
  return {
    id, playerIndex: p, legNo: s.legNo, visitNo: s.visitsInLeg[p] + 1,
    startScore: ev.scoreBefore, scoreAfter: ev.scoreAfter, enteredTotal: ev.enteredTotal,
    points: ev.points, bust: ev.outcome === 'bust', checkout: ev.outcome === 'checkout',
    darts, dartsThrown: ev.dartsCounted, checkoutAttempts: attempts,
    mode: input.kind === 'darts' ? 'perDart' : 'total', timestamp: now.toISOString(),
  };
}
