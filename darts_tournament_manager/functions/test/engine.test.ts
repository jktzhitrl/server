import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  buildVisit, canFinishWithDarts, decodeDart, evaluateDarts, evaluateTotal, isReachableTotal,
  OutMode, replay, Rules, X01Json,
} from '../src/engine';
import { canConfirm, canEnterScores, effectiveRole } from '../src/permissions';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const vectors = require('../../test/vectors.json');

function norm(e: any) {
  return { outcome: e.outcome, scoreAfter: e.scoreAfter, points: e.points, enteredTotal: e.enteredTotal,
    dartsCounted: e.dartsCounted, openedAfter: e.openedAfter };
}

describe('Parität mit der Dart-Implementierung', () => {
  it('Aufnahmen aus Einzeldarts', () => {
    let n = 0;
    for (const c of vectors.dartCases) {
      let actual: any;
      try {
        actual = norm(evaluateDarts(c.remaining, c.opened, c.darts.map(decodeDart), { outMode: c.outMode, inMode: c.inMode }));
      } catch { actual = { error: true }; }
      assert.deepEqual(actual, c.expected, JSON.stringify(c));
      n++;
    }
    assert.ok(n > 3000);
  });
  it('Aufnahmen aus Gesamtpunkten', () => {
    for (const c of vectors.totalCases) {
      let actual: any;
      try {
        actual = norm(evaluateTotal(c.remaining, true, c.total, { outMode: c.outMode, inMode: 'straight' }, c.dartsUsed, c.bust));
      } catch { actual = { error: true }; }
      assert.deepEqual(actual, c.expected, JSON.stringify(c));
    }
  });
  it('Checkout-Tabelle und erreichbare Summen', () => {
    for (const out of ['single', 'double', 'master'] as OutMode[]) {
      for (let s = 0; s <= 200; s++) {
        for (let n = 1; n <= 3; n++) {
          assert.equal(canFinishWithDarts(s, n, out), vectors.finishTable[out][s][n - 1], `${out} ${s} ${n}`);
        }
      }
    }
    for (let t = 0; t <= 200; t++) {
      for (let n = 1; n <= 3; n++) assert.equal(isReachableTotal(t, n), vectors.reachable[t][n - 1], `${t} ${n}`);
    }
  });
});

const rules = (over: Partial<Rules> = {}): Rules => ({
  startScore: 301, inMode: 'straight', outMode: 'double',
  format: { legsToWinSet: 2, setsToWin: 1 }, starterRule: 'alternating', ...over,
});
const match = (over: Partial<Rules> = {}): X01Json => ({ rules: rules(over), playerIds: ['a', 'b'], visits: [] });
const now = new Date('2025-01-01T00:00:00Z');
const T20 = 320; const D20 = 220; const D14 = 214; const T11 = 311; const S20 = 120;

function add(m: X01Json, input: Parameters<typeof buildVisit>[1], id = 'v'): X01Json {
  return { ...m, visits: [...m.visits, buildVisit(m, input, `${id}${m.visits.length}`, now)] };
}

describe('Server-Validierung (buildVisit)', () => {
  it('trägt Aufnahmen ein und wechselt den Spieler', () => {
    let m = add(match(), { kind: 'darts', darts: [T20, T20, T20] });
    assert.equal(m.visits[0].scoreAfter, 121);
    assert.equal(replay(m).currentPlayer, 1);
    m = add(m, { kind: 'total', total: 26 });
    assert.deepEqual(replay(m).remaining, [121, 275]);
  });
  it('erkennt Checkout und Matchende', () => {
    let m = match({ startScore: 40, format: { legsToWinSet: 1, setsToWin: 1 } });
    m = add(m, { kind: 'darts', darts: [D20] });
    assert.equal(replay(m).winnerIndex, 0);
    assert.throws(() => buildVisit(m, { kind: 'total', total: 1 }, 'x', now), /bereits beendet/);
  });
  it('Bust bei Rest 1 und ungültigem Finish; Client kann Ergebnis nicht fälschen', () => {
    let m = match({ startScore: 41 });
    m = add(m, { kind: 'darts', darts: [S20, S20] });
    assert.equal(m.visits[0].bust, true);
    assert.equal(m.visits[0].scoreAfter, 41);
    assert.throws(() => buildVisit(match({ startScore: 100 }), { kind: 'total', total: 100, dartsUsed: 1 }, 'x', now));
    assert.throws(() => buildVisit(match(), { kind: 'total', total: 179 }, 'x', now));
    assert.throws(() => buildVisit(match(), { kind: 'darts', darts: [999, 0, 0] }, 'x', now));
    assert.throws(() => buildVisit(match(), { kind: 'darts', darts: [350, 0, 0] }, 'x', now)); // Triple-Bull
  });
  it('komplettes Leg 301 mit Checkout T20-T11-D14', () => {
    let m = match({ format: { legsToWinSet: 1, setsToWin: 1 } });
    m = add(m, { kind: 'darts', darts: [T20, T20, T20] });
    m = add(m, { kind: 'total', total: 0 });
    m = add(m, { kind: 'darts', darts: [T20, T11, D14] });
    const s = replay(m);
    assert.equal(s.winnerIndex, 0);
    assert.equal(m.visits[2].checkout, true);
    assert.equal(m.visits[2].checkoutAttempts, 1);
  });
  it('Replay erkennt ein manipuliertes Log', () => {
    let m = add(match(), { kind: 'total', total: 60 });
    m = { ...m, visits: [{ ...m.visits[0], startScore: 123 }] };
    assert.throws(() => replay(m), /Inkonsistent/);
  });
  it('Alternierender Anwurf über Legs', () => {
    let m = match({ startScore: 40 });
    m = add(m, { kind: 'darts', darts: [D20] });
    assert.equal(replay(m).currentPlayer, 1);
  });
});

describe('Rollen', () => {
  it('Berechtigungen', () => {
    assert.equal(effectiveRole('player', 'director'), 'director');
    assert.equal(effectiveRole('admin', 'player'), 'admin');
    assert.ok(canEnterScores('scorer'));
    assert.ok(!canEnterScores('player'));
    assert.ok(!canEnterScores('spectator'));
    assert.ok(canConfirm('director'));
    assert.ok(!canConfirm('scorer'));
  });
});
