import '../core/auth/permissions.dart';
import '../core/games/around_the_clock.dart';
import '../core/games/cricket.dart';
import '../core/models/dart_throw.dart';
import '../core/models/rules.dart';
import '../core/tournament/participant.dart';
import '../core/tournament/tournament_plan.dart';
import '../core/x01/x01_match.dart';

/// Angemeldeter Benutzer (Collection `users`).
class AppUser {
  final String uid;
  final String displayName;
  final String? email;

  /// Globale Rolle (nur Admins dürfen sie ändern - per Security Rules).
  final Role role;

  /// Verknüpftes Spielerprofil (Collection `players`).
  final String? playerId;
  const AppUser({
    required this.uid,
    required this.displayName,
    this.email,
    this.role = Role.player,
    this.playerId,
  });

  AppUser copyWith({String? displayName, Role? role, String? playerId}) => AppUser(
        uid: uid,
        displayName: displayName ?? this.displayName,
        email: email,
        role: role ?? this.role,
        playerId: playerId ?? this.playerId,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'email': email,
        'role': role.name,
        'playerId': playerId,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        uid: j['uid'] as String,
        displayName: (j['displayName'] as String?) ?? 'Spieler',
        email: j['email'] as String?,
        role: Role.values.asNameMap()[j['role']] ?? Role.player,
        playerId: j['playerId'] as String?,
      );
}

/// Spielerprofil (Collection `players`) - kann auch ein Gast ohne Konto sein.
class PlayerProfile {
  final String id;
  final String name;
  final String? uid;

  /// Lieblingsdoppel (1..20, 25 = Bull).
  final int? favoriteDouble;
  const PlayerProfile({required this.id, required this.name, this.uid, this.favoriteDouble});

  PlayerProfile copyWith({String? name, int? favoriteDouble, bool clearFavorite = false}) =>
      PlayerProfile(
        id: id,
        name: name ?? this.name,
        uid: uid,
        favoriteDouble: clearFavorite ? null : (favoriteDouble ?? this.favoriteDouble),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'uid': uid, 'favoriteDouble': favoriteDouble};

  factory PlayerProfile.fromJson(Map<String, dynamic> j) => PlayerProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        uid: j['uid'] as String?,
        favoriteDouble: (j['favoriteDouble'] as num?)?.toInt(),
      );
}

enum TournamentStatus { registration, drawn, running, finished }

class BoardInfo {
  final String id;
  final String name;
  final String? currentMatchId;
  const BoardInfo(this.id, this.name, {this.currentMatchId});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'currentMatchId': currentMatchId};
  factory BoardInfo.fromJson(Map<String, dynamic> j) =>
      BoardInfo(j['id'] as String, j['name'] as String, currentMatchId: j['currentMatchId'] as String?);
}

/// Turnier (Collection `tournaments`).
class TournamentRecord {
  final String id;
  final String name;
  final TournamentFormat format;
  final GameType gameType;
  final X01Rules rules;
  final bool isPublic;
  final TournamentStatus status;
  final String inviteCode;
  final String createdBy;
  final DateTime createdAt;

  /// Angemeldete Teilnehmer vor der Auslosung.
  final List<Participant> registrations;

  /// Auslosung/Turnierstand; `null` solange nicht ausgelost.
  final TournamentPlan? plan;

  /// Auslosung für Zuschauer/Spieler sichtbar (Veröffentlichung durch die Leitung).
  final bool published;
  final List<BoardInfo> boards;
  final int version;

  const TournamentRecord({
    required this.id,
    required this.name,
    required this.format,
    required this.gameType,
    required this.rules,
    required this.isPublic,
    required this.status,
    required this.inviteCode,
    required this.createdBy,
    required this.createdAt,
    this.registrations = const [],
    this.plan,
    this.published = false,
    this.boards = const [],
    this.version = 0,
  });

  TournamentRecord copyWith({
    String? name,
    X01Rules? rules,
    bool? isPublic,
    TournamentStatus? status,
    List<Participant>? registrations,
    TournamentPlan? plan,
    bool clearPlan = false,
    bool? published,
    List<BoardInfo>? boards,
    int? version,
  }) =>
      TournamentRecord(
        id: id,
        name: name ?? this.name,
        format: format,
        gameType: gameType,
        rules: rules ?? this.rules,
        isPublic: isPublic ?? this.isPublic,
        status: status ?? this.status,
        inviteCode: inviteCode,
        createdBy: createdBy,
        createdAt: createdAt,
        registrations: registrations ?? this.registrations,
        plan: clearPlan ? null : (plan ?? this.plan),
        published: published ?? this.published,
        boards: boards ?? this.boards,
        version: version ?? this.version,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'format': format.name,
        'gameType': gameType.name,
        'rules': rules.toJson(),
        'isPublic': isPublic,
        'status': status.name,
        'inviteCode': inviteCode,
        'createdBy': createdBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'registrations': registrations.map((p) => p.toJson()).toList(),
        'plan': plan?.toJson(),
        'published': published,
        'boards': boards.map((b) => b.toJson()).toList(),
        'version': version,
      };

  factory TournamentRecord.fromJson(Map<String, dynamic> j) => TournamentRecord(
        id: j['id'] as String,
        name: j['name'] as String,
        format: TournamentFormat.values.byName(j['format'] as String),
        gameType: GameType.values.byName(j['gameType'] as String),
        rules: X01Rules.fromJson(Map<String, dynamic>.from(j['rules'] as Map)),
        isPublic: j['isPublic'] as bool? ?? false,
        status: TournamentStatus.values.byName(j['status'] as String),
        inviteCode: j['inviteCode'] as String,
        createdBy: j['createdBy'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        registrations: [
          for (final p in (j['registrations'] as List? ?? []))
            Participant.fromJson(Map<String, dynamic>.from(p as Map))
        ],
        plan: j['plan'] == null
            ? null
            : TournamentPlan.fromJson(Map<String, dynamic>.from(j['plan'] as Map)),
        published: j['published'] as bool? ?? false,
        boards: [
          for (final b in (j['boards'] as List? ?? []))
            BoardInfo.fromJson(Map<String, dynamic>.from(b as Map))
        ],
        version: (j['version'] as num?)?.toInt() ?? 0,
      );
}

enum MatchStatus { scheduled, live, paused, awaitingConfirmation, confirmed }

class MatchPlayer {
  final String id;
  final String name;
  const MatchPlayer(this.id, this.name);
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory MatchPlayer.fromJson(Map<String, dynamic> j) =>
      MatchPlayer(j['id'] as String, j['name'] as String);
}

/// Begegnung (Collection `matches`): enthält das komplette Event-Log
/// (Aufnahmen bzw. Darts) und wird per optimistischer Versionsnummer
/// gegen gleichzeitige Eingaben geschützt.
class MatchRecord {
  final String id;
  final String? tournamentId;
  final String? planMatchId;
  final GameType gameType;
  final List<MatchPlayer> players;
  final MatchStatus status;
  final String? boardId;
  final String? scorerUid;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPublic;

  final X01Match? x01;
  final CricketMatch? cricket;
  final AroundTheClockMatch? clock;

  /// Laufende, noch nicht abgeschlossene Aufnahme (Modus A) - wird mit
  /// synchronisiert, damit alle Geräte die aktuelle Aufnahme sehen.
  final List<DartThrow> draft;

  const MatchRecord({
    required this.id,
    required this.gameType,
    required this.players,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.tournamentId,
    this.planMatchId,
    this.boardId,
    this.scorerUid,
    this.isPublic = true,
    this.x01,
    this.cricket,
    this.clock,
    this.draft = const [],
  });

  /// Index des Siegers, falls entschieden.
  int? get winnerIndex => x01?.state.winnerIndex ?? cricket?.state.winnerIndex ?? clock?.state.winnerIndex;
  bool get isFinished => winnerIndex != null;
  String? get winnerId => winnerIndex == null ? null : players[winnerIndex!].id;

  MatchRecord copyWith({
    MatchStatus? status,
    String? boardId,
    bool clearBoard = false,
    String? scorerUid,
    X01Match? x01,
    CricketMatch? cricket,
    AroundTheClockMatch? clock,
    List<DartThrow>? draft,
    int? version,
    DateTime? updatedAt,
  }) =>
      MatchRecord(
        id: id,
        tournamentId: tournamentId,
        planMatchId: planMatchId,
        gameType: gameType,
        players: players,
        status: status ?? this.status,
        boardId: clearBoard ? null : (boardId ?? this.boardId),
        scorerUid: scorerUid ?? this.scorerUid,
        version: version ?? this.version,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isPublic: isPublic,
        x01: x01 ?? this.x01,
        cricket: cricket ?? this.cricket,
        clock: clock ?? this.clock,
        draft: draft ?? this.draft,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tournamentId': tournamentId,
        'planMatchId': planMatchId,
        'gameType': gameType.name,
        'players': players.map((p) => p.toJson()).toList(),
        'playerIds': players.map((p) => p.id).toList(),
        'status': status.name,
        'boardId': boardId,
        'scorerUid': scorerUid,
        'version': version,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'isPublic': isPublic,
        'winnerId': winnerId,
        'x01': x01?.toJson(),
        'draft': draft.map((d) => d.toJson()).toList(),
        'cricket': cricket == null
            ? null
            : {
                'cutThroat': cricket!.cutThroat,
                'darts': cricket!.darts.map((d) => d.toJson()).toList(),
              },
        'clock': clock == null
            ? null
            : {
                'skipAhead': clock!.skipAhead,
                'darts': clock!.darts.map((d) => d.toJson()).toList(),
              },
      };

  factory MatchRecord.fromJson(Map<String, dynamic> j) {
    final players = [
      for (final p in j['players'] as List) MatchPlayer.fromJson(Map<String, dynamic>.from(p as Map))
    ];
    final ids = players.map((p) => p.id).toList();
    final c = j['cricket'] == null ? null : Map<String, dynamic>.from(j['cricket'] as Map);
    final k = j['clock'] == null ? null : Map<String, dynamic>.from(j['clock'] as Map);
    return MatchRecord(
      id: j['id'] as String,
      tournamentId: j['tournamentId'] as String?,
      planMatchId: j['planMatchId'] as String?,
      gameType: GameType.values.byName(j['gameType'] as String),
      players: players,
      status: MatchStatus.values.byName(j['status'] as String),
      boardId: j['boardId'] as String?,
      scorerUid: j['scorerUid'] as String?,
      version: (j['version'] as num).toInt(),
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      isPublic: j['isPublic'] as bool? ?? true,
      draft: [for (final d in (j['draft'] as List? ?? [])) DartThrow.fromJson(d)],
      x01: j['x01'] == null ? null : X01Match.fromJson(Map<String, dynamic>.from(j['x01'] as Map)),
      cricket: c == null
          ? null
          : CricketMatch(
              playerIds: ids,
              cutThroat: c['cutThroat'] as bool? ?? false,
              darts: [for (final d in c['darts'] as List) DartThrow.fromJson(d)]),
      clock: k == null
          ? null
          : AroundTheClockMatch(
              playerIds: ids,
              skipAhead: k['skipAhead'] as bool? ?? false,
              darts: [for (final d in k['darts'] as List) DartThrow.fromJson(d)]),
    );
  }
}

/// Protokolleintrag (Collection `audit_logs`) mit Zeitstempel.
class AuditEntry {
  final String id;
  final DateTime at;
  final String uid;
  final String action;
  final String? tournamentId;
  final String? matchId;
  final String detail;
  const AuditEntry({
    required this.id,
    required this.at,
    required this.uid,
    required this.action,
    this.tournamentId,
    this.matchId,
    this.detail = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toUtc().toIso8601String(),
        'uid': uid,
        'action': action,
        'tournamentId': tournamentId,
        'matchId': matchId,
        'detail': detail,
      };

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: j['id'] as String,
        at: DateTime.parse(j['at'] as String),
        uid: j['uid'] as String,
        action: j['action'] as String,
        tournamentId: j['tournamentId'] as String?,
        matchId: j['matchId'] as String?,
        detail: (j['detail'] as String?) ?? '',
      );
}

/// Mitglied eines Turniers (Subcollection `tournaments/{id}/members`).
class TournamentMember {
  final String uid;
  final String name;
  final Role role;
  const TournamentMember(this.uid, this.name, this.role);
  Map<String, dynamic> toJson() => {'uid': uid, 'name': name, 'role': role.name};
  factory TournamentMember.fromJson(Map<String, dynamic> j) => TournamentMember(
      j['uid'] as String, (j['name'] as String?) ?? '', Role.values.byName(j['role'] as String));
}
