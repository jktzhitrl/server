import 'dart:async';
import 'dart:convert';

import '../core/auth/permissions.dart';
import 'models.dart';
import 'repository.dart';

/// Repository im Arbeitsspeicher mit optionaler Persistenz (JSON-String).
/// Dient als Demo-/Offline-Modus (ohne Firebase) und als Testdouble mit
/// derselben Versionsprüfung wie die Firestore-Implementierung.
///
/// Dokumente werden als JSON abgelegt und bei jedem Lesen neu geparst,
/// damit Aufrufer keine gemeinsamen veränderlichen Objekte teilen.
class LocalRepository implements AppRepository {
  final Map<String, Map<String, dynamic>> _tournaments = {};
  final Map<String, Map<String, Map<String, dynamic>>> _members = {};
  final Map<String, Map<String, dynamic>> _matches = {};
  final Map<String, Map<String, dynamic>> _players = {};
  final Map<String, Map<String, dynamic>> _users = {};
  final List<Map<String, dynamic>> _audit = [];
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);
  final Future<void> Function(String json)? _persist;

  LocalRepository({String? initialJson, Future<void> Function(String json)? persist})
      : _persist = persist {
    if (initialJson != null && initialJson.isNotEmpty) {
      try {
        final j = jsonDecode(initialJson) as Map<String, dynamic>;
        _load(_tournaments, j['tournaments']);
        _load(_matches, j['matches']);
        _load(_players, j['players']);
        _load(_users, j['users']);
        (j['members'] as Map? ?? {}).forEach((k, v) {
          _members[k as String] = {
            for (final e in (v as Map).entries)
              e.key as String: Map<String, dynamic>.from(e.value as Map)
          };
        });
        _audit.addAll([
          for (final a in (j['audit'] as List? ?? [])) Map<String, dynamic>.from(a as Map)
        ]);
      } catch (_) {
        // Beschädigte Offline-Daten ignorieren; es wird neu begonnen.
      }
    }
  }

  static void _load(Map<String, Map<String, dynamic>> into, dynamic src) {
    (src as Map? ?? {}).forEach((k, v) => into[k as String] = Map<String, dynamic>.from(v as Map));
  }

  String exportJson() => jsonEncode({
        'tournaments': _tournaments,
        'matches': _matches,
        'players': _players,
        'users': _users,
        'members': _members,
        'audit': _audit,
      });

  void _changed() {
    _persist?.call(exportJson());
    _changes.add(null);
  }

  Stream<T> _watch<T>(T Function() read) {
    late StreamController<T> c;
    StreamSubscription<void>? sub;
    c = StreamController<T>(
      onListen: () {
        c.add(read());
        sub = _changes.stream.listen((_) => c.add(read()));
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  Map<String, dynamic> _copy(Map<String, dynamic> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  @override
  bool get isRemote => false;

  // ---------------------------------------------------------------- Turniere

  List<TournamentRecord> _allTournaments() {
    final l = _tournaments.values.map((m) => TournamentRecord.fromJson(_copy(m))).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return l;
  }

  @override
  Stream<List<TournamentRecord>> watchTournaments() => _watch(_allTournaments);

  @override
  Stream<TournamentRecord?> watchTournament(String id) => _watch(() {
        final m = _tournaments[id];
        return m == null ? null : TournamentRecord.fromJson(_copy(m));
      });

  @override
  Future<TournamentRecord?> findTournamentByInvite(String code) async {
    final c = code.trim().toUpperCase();
    for (final m in _tournaments.values) {
      if ((m['inviteCode'] as String).toUpperCase() == c) {
        return TournamentRecord.fromJson(_copy(m));
      }
    }
    return null;
  }

  @override
  Future<TournamentRecord> saveTournament(TournamentRecord t) async {
    final existing = _tournaments[t.id];
    if (existing != null && (existing['version'] as num).toInt() != t.version) {
      throw VersionConflict('Das Turnier wurde zwischenzeitlich geändert.');
    }
    final saved = t.copyWith(version: t.version + 1);
    _tournaments[t.id] = _copy(saved.toJson());
    _changed();
    return TournamentRecord.fromJson(_copy(_tournaments[t.id]!));
  }

  @override
  Stream<List<TournamentMember>> watchMembers(String tournamentId) => _watch(() => [
        for (final m in (_members[tournamentId] ?? {}).values) TournamentMember.fromJson(_copy(m))
      ]);

  @override
  Future<void> setMember(String tournamentId, TournamentMember member) async {
    (_members[tournamentId] ??= {})[member.uid] = member.toJson();
    _changed();
  }

  @override
  Future<void> removeMember(String tournamentId, String uid) async {
    _members[tournamentId]?.remove(uid);
    _changed();
  }

  @override
  Future<Role?> memberRole(String tournamentId, String uid) async {
    final m = _members[tournamentId]?[uid];
    return m == null ? null : Role.values.byName(m['role'] as String);
  }

  // ------------------------------------------------------------- Begegnungen

  List<MatchRecord> _matchList({String? tournamentId, bool liveOnly = false}) {
    var l = _matches.values.map((m) => MatchRecord.fromJson(_copy(m))).toList();
    if (tournamentId != null) l = l.where((m) => m.tournamentId == tournamentId).toList();
    if (liveOnly) {
      l = l.where((m) => m.status == MatchStatus.live || m.status == MatchStatus.paused).toList();
    }
    l.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return l;
  }

  @override
  Stream<List<MatchRecord>> watchMatches({String? tournamentId, bool liveOnly = false}) =>
      _watch(() => _matchList(tournamentId: tournamentId, liveOnly: liveOnly));

  @override
  Stream<MatchRecord?> watchMatch(String id) => _watch(() {
        final m = _matches[id];
        return m == null ? null : MatchRecord.fromJson(_copy(m));
      });

  @override
  Future<MatchRecord> createMatch(MatchRecord m) async {
    if (_matches.containsKey(m.id)) throw StateError('Begegnung existiert bereits');
    _matches[m.id] = _copy(m.toJson());
    _changed();
    return MatchRecord.fromJson(_copy(_matches[m.id]!));
  }

  @override
  Future<MatchRecord> updateMatch(
    String id,
    MatchRecord Function(MatchRecord current) mutate, {
    int? expectedVersion,
  }) async {
    final raw = _matches[id];
    if (raw == null) throw StateError('Begegnung $id nicht gefunden');
    final current = MatchRecord.fromJson(_copy(raw));
    if (expectedVersion != null && expectedVersion != current.version) {
      throw VersionConflict();
    }
    final next = mutate(current).copyWith(version: current.version + 1, updatedAt: DateTime.now().toUtc());
    _matches[id] = _copy(next.toJson());
    _changed();
    return MatchRecord.fromJson(_copy(_matches[id]!));
  }

  // ------------------------------------------------------------------ Spieler

  @override
  Stream<List<PlayerProfile>> watchPlayers() => _watch(() => [
        for (final p in _players.values) PlayerProfile.fromJson(_copy(p))
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  @override
  Future<PlayerProfile> savePlayer(PlayerProfile p) async {
    _players[p.id] = p.toJson();
    _changed();
    return p;
  }

  // -------------------------------------------------------------------- Audit

  @override
  Future<void> audit(AuditEntry e) async {
    _audit.add(e.toJson());
    _changed();
  }

  @override
  Stream<List<AuditEntry>> watchAudit({String? tournamentId}) => _watch(() {
        var l = _audit.map((m) => AuditEntry.fromJson(_copy(m))).toList();
        if (tournamentId != null) l = l.where((e) => e.tournamentId == tournamentId).toList();
        l.sort((a, b) => b.at.compareTo(a.at));
        return l;
      });

  // ----------------------------------------------------------------- Benutzer

  @override
  Future<AppUser?> getUser(String uid) async {
    final m = _users[uid];
    return m == null ? null : AppUser.fromJson(_copy(m));
  }

  @override
  Future<void> saveUser(AppUser u) async {
    _users[u.uid] = u.toJson();
    _changed();
  }

  @override
  Stream<List<AppUser>> watchUsers() => _watch(() => [
        for (final u in _users.values) AppUser.fromJson(_copy(u))
      ]);
}
