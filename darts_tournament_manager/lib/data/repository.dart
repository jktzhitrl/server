import '../core/auth/permissions.dart';
import 'models.dart';

/// Wird geworfen, wenn eine Schreiboperation auf einem veralteten Stand
/// basiert (zwei Schreiber gleichzeitig / Verbindungsabbruch mit Rückkehr).
class VersionConflict implements Exception {
  final String message;
  VersionConflict([this.message = 'Der Spielstand wurde zwischenzeitlich geändert.']);
  @override
  String toString() => message;
}

class PermissionDenied implements Exception {
  final String message;
  PermissionDenied([this.message = 'Dazu fehlt die Berechtigung.']);
  @override
  String toString() => message;
}

/// Zugriff auf die Daten. Implementierungen: [LocalRepository] (Demo/Offline,
/// ohne Firebase) und `FirestoreRepository` (Echtzeit-Synchronisierung).
abstract class AppRepository {
  /// `true`, wenn Daten über Firebase zwischen Geräten synchronisiert werden.
  bool get isRemote;

  // Turniere
  Stream<List<TournamentRecord>> watchTournaments();
  Stream<TournamentRecord?> watchTournament(String id);
  Future<TournamentRecord?> findTournamentByInvite(String code);

  /// Speichert ein Turnier mit optimistischer Versionsprüfung
  /// (`t.version` muss dem gespeicherten Stand entsprechen, sonst [VersionConflict]).
  Future<TournamentRecord> saveTournament(TournamentRecord t);
  Stream<List<TournamentMember>> watchMembers(String tournamentId);
  Future<void> setMember(String tournamentId, TournamentMember member);
  Future<void> removeMember(String tournamentId, String uid);
  Future<Role?> memberRole(String tournamentId, String uid);

  // Begegnungen
  Stream<List<MatchRecord>> watchMatches({String? tournamentId, bool liveOnly = false});
  Stream<MatchRecord?> watchMatch(String id);
  Future<MatchRecord> createMatch(MatchRecord m);

  /// Atomar ändern: [mutate] bekommt den aktuellen Stand. Ist
  /// [expectedVersion] gesetzt und weicht ab, wird [VersionConflict] geworfen.
  Future<MatchRecord> updateMatch(
    String id,
    MatchRecord Function(MatchRecord current) mutate, {
    int? expectedVersion,
  });

  // Spieler
  Stream<List<PlayerProfile>> watchPlayers();
  Future<PlayerProfile> savePlayer(PlayerProfile p);

  // Audit
  Future<void> audit(AuditEntry e);
  Stream<List<AuditEntry>> watchAudit({String? tournamentId});

  // Benutzer
  Future<AppUser?> getUser(String uid);
  Future<void> saveUser(AppUser u);
  Stream<List<AppUser>> watchUsers();
}
