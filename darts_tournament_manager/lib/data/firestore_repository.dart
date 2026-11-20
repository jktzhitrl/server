import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/auth/permissions.dart';
import 'models.dart';
import 'repository.dart';

/// Firestore-Implementierung mit Echtzeit-Streams.
///
/// Datenmodell (siehe docs/DATA_MODEL.md):
///  * `users/{uid}`, `players/{id}`
///  * `tournaments/{id}` mit Subcollection `members/{uid}`
///  * `matches/{id}` - enthält das vollständige Event-Log (Aufnahmen/Darts),
///    damit eine Eingabe atomar und gegen Konflikte versioniert ist
///  * `audit_logs/{id}`
///
/// Schreibzugriffe laufen über Transaktionen mit Versionsprüfung; die
/// Security Rules erzwingen zusätzlich Rolle und `version == alt + 1`.
/// Firestore speichert Offline-Änderungen lokal und synchronisiert sie nach
/// Wiederherstellung der Verbindung (Persistenz ist standardmäßig aktiv).
class FirestoreRepository implements AppRepository {
  final FirebaseFirestore db;
  FirestoreRepository({FirebaseFirestore? firestore}) : db = firestore ?? FirebaseFirestore.instance;

  @override
  bool get isRemote => true;

  CollectionReference<Map<String, dynamic>> get _tournaments => db.collection('tournaments');
  CollectionReference<Map<String, dynamic>> get _matches => db.collection('matches');
  CollectionReference<Map<String, dynamic>> get _players => db.collection('players');
  CollectionReference<Map<String, dynamic>> get _users => db.collection('users');
  CollectionReference<Map<String, dynamic>> get _audit => db.collection('audit_logs');

  @override
  Stream<List<TournamentRecord>> watchTournaments() => _tournaments
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => [for (final d in s.docs) TournamentRecord.fromJson(d.data())]);

  @override
  Stream<TournamentRecord?> watchTournament(String id) => _tournaments
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? TournamentRecord.fromJson(d.data()!) : null);

  @override
  Future<TournamentRecord?> findTournamentByInvite(String code) async {
    final q = await _tournaments
        .where('inviteCode', isEqualTo: code.trim().toUpperCase())
        .limit(1)
        .get();
    return q.docs.isEmpty ? null : TournamentRecord.fromJson(q.docs.first.data());
  }

  @override
  Future<TournamentRecord> saveTournament(TournamentRecord t) async {
    final ref = _tournaments.doc(t.id);
    return db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists && (snap.data()!['version'] as num).toInt() != t.version) {
        throw VersionConflict('Das Turnier wurde zwischenzeitlich geändert.');
      }
      final saved = t.copyWith(version: t.version + 1);
      tx.set(ref, saved.toJson());
      return saved;
    });
  }

  @override
  Stream<List<TournamentMember>> watchMembers(String tournamentId) =>
      _tournaments.doc(tournamentId).collection('members').snapshots().map(
          (s) => [for (final d in s.docs) TournamentMember.fromJson(d.data())]);

  @override
  Future<void> setMember(String tournamentId, TournamentMember member) =>
      _tournaments.doc(tournamentId).collection('members').doc(member.uid).set(member.toJson());

  @override
  Future<void> removeMember(String tournamentId, String uid) =>
      _tournaments.doc(tournamentId).collection('members').doc(uid).delete();

  @override
  Future<Role?> memberRole(String tournamentId, String uid) async {
    final d = await _tournaments.doc(tournamentId).collection('members').doc(uid).get();
    return d.exists ? Role.values.byName(d.data()!['role'] as String) : null;
  }

  @override
  Stream<List<MatchRecord>> watchMatches({String? tournamentId, bool liveOnly = false}) {
    Query<Map<String, dynamic>> q = _matches;
    if (tournamentId != null) q = q.where('tournamentId', isEqualTo: tournamentId);
    if (liveOnly) q = q.where('status', whereIn: ['live', 'paused']);
    return q.snapshots().map((s) {
      final l = [for (final d in s.docs) MatchRecord.fromJson(d.data())]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return l;
    });
  }

  @override
  Stream<MatchRecord?> watchMatch(String id) =>
      _matches.doc(id).snapshots().map((d) => d.exists ? MatchRecord.fromJson(d.data()!) : null);

  @override
  Future<MatchRecord> createMatch(MatchRecord m) async {
    await _matches.doc(m.id).set(m.toJson());
    return m;
  }

  @override
  Future<MatchRecord> updateMatch(
    String id,
    MatchRecord Function(MatchRecord current) mutate, {
    int? expectedVersion,
  }) {
    final ref = _matches.doc(id);
    return db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Begegnung $id nicht gefunden');
      final current = MatchRecord.fromJson(snap.data()!);
      if (expectedVersion != null && expectedVersion != current.version) {
        throw VersionConflict();
      }
      final next = mutate(current)
          .copyWith(version: current.version + 1, updatedAt: DateTime.now().toUtc());
      tx.set(ref, next.toJson());
      return next;
    });
  }

  @override
  Stream<List<PlayerProfile>> watchPlayers() => _players.snapshots().map((s) => [
        for (final d in s.docs) PlayerProfile.fromJson(d.data())
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  @override
  Future<PlayerProfile> savePlayer(PlayerProfile p) async {
    await _players.doc(p.id).set(p.toJson());
    return p;
  }

  @override
  Future<void> audit(AuditEntry e) => _audit.doc(e.id).set(e.toJson());

  @override
  Stream<List<AuditEntry>> watchAudit({String? tournamentId}) {
    Query<Map<String, dynamic>> q = _audit;
    if (tournamentId != null) q = q.where('tournamentId', isEqualTo: tournamentId);
    return q.snapshots().map((s) => [for (final d in s.docs) AuditEntry.fromJson(d.data())]
      ..sort((a, b) => b.at.compareTo(a.at)));
  }

  @override
  Future<AppUser?> getUser(String uid) async {
    final d = await _users.doc(uid).get();
    return d.exists ? AppUser.fromJson(d.data()!) : null;
  }

  @override
  Future<void> saveUser(AppUser u) => _users.doc(u.uid).set(u.toJson());

  @override
  Stream<List<AppUser>> watchUsers() =>
      _users.snapshots().map((s) => [for (final d in s.docs) AppUser.fromJson(d.data())]);
}
