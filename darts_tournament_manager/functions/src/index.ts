import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { buildVisit, replay, VisitInput, X01Json } from './engine';
import { canEnterScores, effectiveRole, Role } from './permissions';

initializeApp();
const db = getFirestore();

async function roleFor(uid: string, tournamentId: string | null): Promise<Role> {
  const u = await db.doc(`users/${uid}`).get();
  const global = (u.exists ? (u.data()!.role as Role) : 'spectator') ?? 'spectator';
  if (!tournamentId) return global;
  const m = await db.doc(`tournaments/${tournamentId}/members/${uid}`).get();
  return effectiveRole(global, m.exists ? (m.data()!.role as Role) : null);
}

/**
 * Trägt eine Aufnahme serverseitig validiert ein.
 *
 * data: { matchId, expectedVersion, input: VisitInput }
 * - prüft Anmeldung und Rolle (Schreiber/Leitung bzw. Schreiber des Freundschaftsspiels)
 * - prüft die Version (optimistische Sperre) innerhalb einer Transaktion
 * - berechnet Bust/Checkout/Restscore selbst - Werte des Clients werden nie übernommen
 */
export const submitVisit = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Anmeldung erforderlich');
  const { matchId, expectedVersion, input } = request.data as {
    matchId: string; expectedVersion: number; input: VisitInput;
  };
  if (typeof matchId !== 'string' || typeof expectedVersion !== 'number' || !input) {
    throw new HttpsError('invalid-argument', 'matchId, expectedVersion und input sind Pflicht');
  }
  const ref = db.doc(`matches/${matchId}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Begegnung nicht gefunden');
    const m = snap.data()!;
    const tournamentId = (m.tournamentId as string | null) ?? null;

    const role = await roleFor(uid, tournamentId);
    const allowed = tournamentId
      ? canEnterScores(role)
      : m.scorerUid === uid || role === 'admin';
    if (!allowed) throw new HttpsError('permission-denied', 'Keine Berechtigung zur Eingabe');
    if (m.status === 'paused') throw new HttpsError('failed-precondition', 'Das Spiel ist pausiert');
    if (m.status === 'confirmed') throw new HttpsError('failed-precondition', 'Ergebnis bereits bestätigt');
    if (m.version !== expectedVersion) {
      throw new HttpsError('aborted', `Versionskonflikt: erwartet ${expectedVersion}, aktuell ${m.version}`);
    }
    const x01 = m.x01 as X01Json | null;
    if (!x01) throw new HttpsError('failed-precondition', 'Kein X01-Spiel');

    let visit;
    try {
      visit = buildVisit(x01, input, `v${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`, new Date());
    } catch (e) {
      throw new HttpsError('invalid-argument', (e as Error).message);
    }
    const updated: X01Json = { ...x01, visits: [...x01.visits, visit] };
    const state = replay(updated);
    const finished = state.winnerIndex !== null;
    tx.update(ref, {
      x01: updated,
      draft: [],
      version: m.version + 1,
      updatedAt: new Date().toISOString(),
      winnerId: finished ? m.players[state.winnerIndex!].id : null,
      status: finished && !tournamentId ? 'confirmed' : m.status,
    });
    tx.set(db.collection('audit_logs').doc(), {
      at: new Date().toISOString(), uid, action: 'match.visit.server',
      tournamentId, matchId, detail: `${visit.enteredTotal}${visit.bust ? ' (Bust)' : ''}${visit.checkout ? ' (Checkout)' : ''}`,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { version: m.version + 1, bust: visit.bust, checkout: visit.checkout, finished };
  });
});
