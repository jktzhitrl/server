// Tests für ../firestore.rules - laufen gegen den Firestore-Emulator:
//   npm test   (startet den Emulator automatisch über firebase emulators:exec)
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, addDoc, collection, deleteDoc } from 'firebase/firestore';

let env;

const user = (uid, role = 'player', playerId = `pl-${uid}`) => ({
  uid, displayName: uid, email: `${uid}@example.org`, role, playerId,
});

function tournament(over = {}) {
  return {
    id: 't1', name: 'Test', format: 'singleElimination', gameType: 'x501',
    rules: {}, isPublic: false, status: 'registration', inviteCode: 'ABC234',
    createdBy: 'admin', createdAt: '2025-01-01T00:00:00Z', registrations: [],
    plan: null, published: false, boards: [], version: 1, ...over,
  };
}

function visit(over = {}) {
  return { id: 'v', playerIndex: 0, legNo: 1, visitNo: 1, startScore: 501, scoreAfter: 441,
    enteredTotal: 60, points: 60, bust: false, checkout: false, darts: null,
    dartsThrown: 3, checkoutAttempts: null, mode: 'total', timestamp: '2025-01-01T00:00:00Z', ...over };
}

function match(over = {}) {
  return {
    id: 'm1', tournamentId: 't1', planMatchId: 'W-r1-m0', gameType: 'x501',
    players: [{ id: 'a', name: 'A' }, { id: 'b', name: 'B' }], playerIds: ['a', 'b'],
    status: 'live', boardId: null, scorerUid: 'scorer', version: 1,
    createdAt: '2025-01-01T00:00:00Z', updatedAt: '2025-01-01T00:00:00Z', isPublic: false,
    winnerId: null, x01: { rules: {}, playerIds: ['a', 'b'], visits: [] }, draft: [], cricket: null, clock: null,
    ...over,
  };
}

const db = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-darts',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    for (const u of [user('admin', 'admin'), user('dir', 'player'), user('scorer', 'player'),
      user('pl', 'player'), user('other', 'player'), user('globalScorer', 'scorer')]) {
      await setDoc(doc(f, 'users', u.uid), u);
    }
    await setDoc(doc(f, 'tournaments/t1'), tournament());
    await setDoc(doc(f, 'tournaments/t1/members/dir'), { uid: 'dir', name: 'dir', role: 'director' });
    await setDoc(doc(f, 'tournaments/t1/members/scorer'), { uid: 'scorer', name: 'scorer', role: 'scorer' });
    await setDoc(doc(f, 'tournaments/t2'), tournament({ id: 't2', name: 'Anderes', isPublic: true }));
    await setDoc(doc(f, 'tournaments/t2/members/other'), { uid: 'other', name: 'other', role: 'scorer' });
    await setDoc(doc(f, 'matches/m1'), match());
  });
});

describe('Benutzer und Rollen', () => {
  it('neues Konto nur als player', async () => {
    await assertSucceeds(setDoc(doc(db('new1'), 'users/new1'), user('new1', 'player')));
    await assertFails(setDoc(doc(db('new2'), 'users/new2'), user('new2', 'admin')));
    await assertFails(setDoc(doc(db('new3'), 'users/new3'), user('new3', 'director')));
  });
  it('keine Selbstbeförderung, Admin darf Rollen ändern', async () => {
    await assertFails(updateDoc(doc(db('pl'), 'users/pl'), { role: 'admin' }));
    await assertSucceeds(updateDoc(doc(db('pl'), 'users/pl'), { displayName: 'Neu' }));
    await assertSucceeds(updateDoc(doc(db('admin'), 'users/pl'), { role: 'scorer' }));
  });
  it('fremde Benutzerprofile (E-Mail) sind nicht lesbar', async () => {
    await assertFails(getDoc(doc(db('pl'), 'users/other')));
    await assertSucceeds(getDoc(doc(db('pl'), 'users/pl')));
    await assertSucceeds(getDoc(doc(db('admin'), 'users/pl')));
  });
});

describe('Turniere', () => {
  it('nur Admins legen Turniere an', async () => {
    const t = tournament({ id: 'new', createdBy: 'pl' });
    await assertFails(setDoc(doc(db('pl'), 'tournaments/new'), t));
    await assertFails(setDoc(doc(db('dir'), 'tournaments/new'), { ...t, createdBy: 'dir' }));
    await assertSucceeds(setDoc(doc(db('admin'), 'tournaments/new'), { ...t, createdBy: 'admin' }));
    await assertFails(setDoc(doc(db('admin'), 'tournaments/new2'), { ...t, id: 'new2', createdBy: 'admin', version: 5 }));
  });
  it('Leitung darf ändern, aber nur mit Versionssprung +1', async () => {
    await assertSucceeds(updateDoc(doc(db('dir'), 'tournaments/t1'), { name: 'Neu', version: 2 }));
    await assertFails(updateDoc(doc(db('dir'), 'tournaments/t1'), { name: 'Neu2', version: 2 })); // veraltet
    await assertFails(updateDoc(doc(db('dir'), 'tournaments/t1'), { name: 'Neu3', version: 9 }));
  });
  it('unveränderliche Felder', async () => {
    await assertFails(updateDoc(doc(db('admin'), 'tournaments/t1'), { inviteCode: 'HACKED', version: 2 }));
    await assertFails(updateDoc(doc(db('admin'), 'tournaments/t1'), { createdBy: 'pl', version: 2 }));
  });
  it('Selbstanmeldung: genau man selbst, nur in der Anmeldephase', async () => {
    const me = { id: 'pl-pl', name: 'pl', seed: null };
    await assertSucceeds(updateDoc(doc(db('pl'), 'tournaments/t1'), { registrations: [me], version: 2 }));
    // fremden Spieler eintragen
    await assertFails(updateDoc(doc(db('other'), 'tournaments/t1'), {
      registrations: [{ id: 'pl-pl', name: 'pl' }], version: 2 }));
    // zwei auf einmal
    await assertFails(updateDoc(doc(db('pl'), 'tournaments/t1'), {
      registrations: [me, { id: 'x', name: 'x' }], version: 2 }));
    // andere Felder gleichzeitig
    await assertFails(updateDoc(doc(db('pl'), 'tournaments/t1'), {
      registrations: [me], name: 'Hack', version: 2 }));
  });
  it('Selbstanmeldung nach Auslosung gesperrt', async () => {
    await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'tournaments/t1'), { status: 'drawn' }));
    await assertFails(updateDoc(doc(db('pl'), 'tournaments/t1'), {
      registrations: [{ id: 'pl-pl', name: 'pl' }], version: 2 }));
  });
  it('Schreiber ändert nur die Boardbelegung', async () => {
    await assertSucceeds(updateDoc(doc(db('scorer'), 'tournaments/t1'), { boards: [{ id: 'b1', name: 'B1', currentMatchId: 'm1' }], version: 2 }));
    await assertFails(updateDoc(doc(db('scorer'), 'tournaments/t1'), { published: true, version: 2 }));
    await assertFails(updateDoc(doc(db('scorer'), 'tournaments/t1'), { plan: { x: 1 }, version: 2 }));
  });
  it('Unbeteiligte Spieler und Zuschauer dürfen nichts ändern', async () => {
    await assertFails(updateDoc(doc(db('other'), 'tournaments/t1'), { name: 'x', version: 2 }));
    await assertFails(deleteDoc(doc(db('dir'), 'tournaments/t1')));
    await assertSucceeds(deleteDoc(doc(db('admin'), 'tournaments/t1')));
  });
  it('Lesen: Angemeldete alles, Anonyme nur öffentliche', async () => {
    await assertSucceeds(getDoc(doc(db('pl'), 'tournaments/t1')));
    await assertSucceeds(getDoc(doc(anon(), 'tournaments/t2')));
    await assertFails(getDoc(doc(anon(), 'tournaments/t1')));
  });
  it('Anonyme können nie schreiben', async () => {
    await assertFails(setDoc(doc(anon(), 'tournaments/x'), tournament({ id: 'x' })));
    await assertFails(updateDoc(doc(anon(), 'tournaments/t2'), { name: 'x', version: 2 }));
  });
});

describe('Turnier-Mitglieder', () => {
  it('Spieler kann sich nicht zum Schreiber machen', async () => {
    await assertSucceeds(setDoc(doc(db('pl'), 'tournaments/t1/members/pl'), { uid: 'pl', name: 'pl', role: 'player' }));
    await assertFails(setDoc(doc(db('other'), 'tournaments/t1/members/other'), { uid: 'other', name: 'o', role: 'scorer' }));
    await assertFails(setDoc(doc(db('other'), 'tournaments/t1/members/other'), { uid: 'other', name: 'o', role: 'director' }));
  });
  it('bestehende Rolle kann nicht selbst überschrieben werden', async () => {
    await assertFails(setDoc(doc(db('scorer'), 'tournaments/t1/members/scorer'), { uid: 'scorer', name: 's', role: 'player' }));
  });
  it('Leitung vergibt Schreiber, aber keine Leitung; Admin alles', async () => {
    await assertSucceeds(setDoc(doc(db('dir'), 'tournaments/t1/members/pl'), { uid: 'pl', name: 'pl', role: 'scorer' }));
    await assertFails(setDoc(doc(db('dir'), 'tournaments/t1/members/pl'), { uid: 'pl', name: 'pl', role: 'director' }));
    await assertSucceeds(setDoc(doc(db('admin'), 'tournaments/t1/members/pl'), { uid: 'pl', name: 'pl', role: 'director' }));
  });
});

describe('Begegnungen und gleichzeitige Eingaben', () => {
  it('Schreiber des Turniers darf eintragen (Version +1)', async () => {
    const v = visit();
    await assertSucceeds(updateDoc(doc(db('scorer'), 'matches/m1'), {
      x01: { rules: {}, playerIds: ['a', 'b'], visits: [v] }, version: 2 }));
  });
  it('zweiter Schreiber mit altem Stand wird abgewiesen', async () => {
    await assertSucceeds(updateDoc(doc(db('scorer'), 'matches/m1'), { draft: [320], version: 2 }));
    await assertFails(updateDoc(doc(db('dir'), 'matches/m1'), { draft: [120], version: 2 }));
    await assertSucceeds(updateDoc(doc(db('dir'), 'matches/m1'), { draft: [120], version: 3 }));
  });
  it('Spieler, Zuschauer und fremde Schreiber dürfen nicht eingeben', async () => {
    for (const uid of ['pl', 'other', 'nobody']) {
      await assertFails(updateDoc(doc(db(uid), 'matches/m1'), { draft: [120], version: 2 }));
    }
    await assertFails(updateDoc(doc(anon(), 'matches/m1'), { draft: [120], version: 2 }));
  });
  it('globaler Schreiber darf', async () => {
    await assertSucceeds(updateDoc(doc(db('globalScorer'), 'matches/m1'), { draft: [120], version: 2 }));
  });
  it('Bestätigen nur durch die Turnierleitung', async () => {
    await assertFails(updateDoc(doc(db('scorer'), 'matches/m1'), { status: 'confirmed', version: 2 }));
    await assertSucceeds(updateDoc(doc(db('scorer'), 'matches/m1'), { status: 'awaitingConfirmation', version: 2 }));
    await assertSucceeds(updateDoc(doc(db('dir'), 'matches/m1'), { status: 'confirmed', version: 3 }));
  });
  it('Plausibilität: Punkte 0..180, Darts 1..3, nur eine Aufnahme je Schreibvorgang', async () => {
    const ref = doc(db('scorer'), 'matches/m1');
    const wrap = (visits) => ({ x01: { rules: {}, playerIds: ['a', 'b'], visits }, version: 2 });
    await assertFails(updateDoc(ref, wrap([visit({ points: 181 })])));
    await assertFails(updateDoc(ref, wrap([visit({ points: -5 })])));
    await assertFails(updateDoc(ref, wrap([visit({ dartsThrown: 4 })])));
    await assertFails(updateDoc(ref, wrap([visit({ dartsThrown: 0 })])));
    await assertFails(updateDoc(ref, wrap([visit(), visit({ id: 'v2' })])));
    await assertSucceeds(updateDoc(ref, wrap([visit({ points: 180, dartsThrown: 3 })])));
  });
  it('unveränderliche Felder (Spieler, Turnier)', async () => {
    await assertFails(updateDoc(doc(db('dir'), 'matches/m1'), { players: [{ id: 'x', name: 'X' }], version: 2 }));
    await assertFails(updateDoc(doc(db('dir'), 'matches/m1'), { tournamentId: 't2', version: 2 }));
  });
  it('Turnier-Begegnung anlegen: nur Schreiber/Leitung', async () => {
    const m = match({ id: 'm2', version: 0, planMatchId: 'W-r1-m1' });
    await assertFails(setDoc(doc(db('pl'), 'matches/m2'), m));
    await assertSucceeds(setDoc(doc(db('scorer'), 'matches/m2'), m));
    await assertFails(setDoc(doc(db('scorer'), 'matches/m3'), { ...m, id: 'm3', version: 7 }));
  });
  it('Freundschaftsspiel: jeder Angemeldete, aber nur der Schreiber ändert', async () => {
    const f = match({ id: 'f1', tournamentId: null, planMatchId: null, version: 0, scorerUid: 'pl' });
    await assertSucceeds(setDoc(doc(db('pl'), 'matches/f1'), f));
    await assertFails(setDoc(doc(db('pl'), 'matches/f2'), { ...f, id: 'f2', scorerUid: 'other' }));
    await assertSucceeds(updateDoc(doc(db('pl'), 'matches/f1'), { draft: [120], version: 1 }));
    await assertFails(updateDoc(doc(db('other'), 'matches/f1'), { draft: [120], version: 2 }));
  });
  it('Cricket-Begegnung (ohne x01) ist schreibbar', async () => {
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'matches/c1'),
      match({ id: 'c1', gameType: 'cricket', x01: null, cricket: { cutThroat: false, darts: [] } })));
    await assertSucceeds(updateDoc(doc(db('scorer'), 'matches/c1'),
      { cricket: { cutThroat: false, darts: [320] }, version: 2 }));
  });
  it('Lesen öffentlicher Spiele ohne Anmeldung', async () => {
    await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'matches/m1'), { isPublic: true }));
    await assertSucceeds(getDoc(doc(anon(), 'matches/m1')));
  });
});

describe('Spieler und Audit-Log', () => {
  it('Spielerprofile: eigenes bearbeiten, fremdes nicht', async () => {
    await assertSucceeds(setDoc(doc(db('pl'), 'players/pl-pl'), { id: 'pl-pl', name: 'pl', uid: 'pl', favoriteDouble: null }));
    await assertSucceeds(updateDoc(doc(db('pl'), 'players/pl-pl'), { favoriteDouble: 16 }));
    await assertFails(updateDoc(doc(db('other'), 'players/pl-pl'), { favoriteDouble: 20 }));
    await assertFails(setDoc(doc(db('other'), 'players/x'), { id: 'x', name: 'x', uid: 'pl' })); // fremde uid
    await assertSucceeds(setDoc(doc(db('other'), 'players/guest'), { id: 'guest', name: 'Gast', uid: null }));
  });
  it('Audit-Log ist append-only', async () => {
    const entry = { id: 'a1', at: '2025-01-01T00:00:00Z', uid: 'dir', action: 'x', tournamentId: 't1', matchId: null, detail: '' };
    await assertSucceeds(setDoc(doc(db('dir'), 'audit_logs/a1'), entry));
    await assertFails(setDoc(doc(db('dir'), 'audit_logs/a2'), { ...entry, id: 'a2', uid: 'someoneElse' })); // fremde uid
    await assertFails(updateDoc(doc(db('dir'), 'audit_logs/a1'), { action: 'y' }));
    await assertFails(deleteDoc(doc(db('admin'), 'audit_logs/a1')));
    await assertSucceeds(getDoc(doc(db('admin'), 'audit_logs/a1')));
    await assertSucceeds(getDoc(doc(db('dir'), 'audit_logs/a1')));
    await assertFails(getDoc(doc(db('pl'), 'audit_logs/a1')));
  });
  it('unbekannte Collections sind gesperrt', async () => {
    await assertFails(setDoc(doc(db('admin'), 'foo/bar'), { a: 1 }));
    await assertFails(getDoc(doc(db('admin'), 'foo/bar')));
  });
});
