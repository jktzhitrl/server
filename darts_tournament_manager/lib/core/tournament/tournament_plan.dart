import 'dart:math';

import 'bracket.dart';
import 'group_stage.dart';
import 'participant.dart';
import 'round_robin.dart';
import 'seeding.dart';
import 'swiss.dart';

enum TournamentFormat {
  singleElimination,
  doubleElimination,
  roundRobin,
  groupsKnockout,
  swiss,
  league,
  friendly,
}

extension TournamentFormatX on TournamentFormat {
  String get label => switch (this) {
        TournamentFormat.singleElimination => 'K.-o.-System',
        TournamentFormat.doubleElimination => 'Doppel-K.-o.',
        TournamentFormat.roundRobin => 'Jeder gegen jeden',
        TournamentFormat.groupsKnockout => 'Gruppenphase + K.-o.',
        TournamentFormat.swiss => 'Schweizer System',
        TournamentFormat.league => 'Liga (Hin- und Rückrunde)',
        TournamentFormat.friendly => 'Freundschaftsspiel',
      };
}

enum PlanPhase { groups, knockout, rounds, finished }

/// Eine aktuell spielbare Begegnung in einheitlicher Form (Baum oder Spielplan).
class PlanMatch {
  final String id;
  final String label;
  final int round;
  final String aId;
  final String bId;
  const PlanMatch(this.id, this.label, this.round, this.aId, this.bId);
  List<String> get playerIds => [aId, bId];
}

/// Konfiguration einer Turnierauslosung.
class PlanOptions {
  final bool useSeeds;
  final int? groupCount;
  final int? groupSize;
  final int advancePerGroup;
  final int? swissRounds;
  final int pointsPerWin;
  final bool doubleRound;
  const PlanOptions({
    this.useSeeds = true,
    this.groupCount,
    this.groupSize = 4,
    this.advancePerGroup = 2,
    this.swissRounds,
    this.pointsPerWin = 2,
    this.doubleRound = false,
  });
}

/// Zustand und Fortschrittslogik eines Turniers (reines Dart, serialisierbar).
///
/// Ablauf: [TournamentPlan.draw] erzeugt die Auslosung (Entwurf). Die
/// Turnierleitung kann Positionen tauschen ([swapPositions]) und danach
/// veröffentlichen. Ergebnisse laufen über [reportResult]; Qualifikation,
/// K.-o.-Phase und Schweizer Folgerunden werden automatisch erzeugt.
class TournamentPlan {
  final TournamentFormat format;
  final List<Participant> participants;
  final PlanOptions options;
  Bracket? bracket;
  List<Fixture> fixtures;
  List<Group> groups;
  PlanPhase phase;
  int swissRound;
  int swissTotalRounds;

  /// Bracket-Positionsliste der Auslosung (für manuelle Anpassung).
  List<String?> positions;

  TournamentPlan._({
    required this.format,
    required this.participants,
    required this.options,
    this.bracket,
    this.fixtures = const [],
    this.groups = const [],
    this.phase = PlanPhase.rounds,
    this.swissRound = 0,
    this.swissTotalRounds = 0,
    this.positions = const [],
  });

  Map<String, String> get names => {for (final p in participants) p.id: p.name};
  List<String> get ids => [for (final p in participants) p.id];
  List<String> get seedOrder {
    final ranked = participants.where((p) => p.seed != null).toList()
      ..sort((a, b) => a.seed!.compareTo(b.seed!));
    return ranked.map((p) => p.id).toList();
  }

  // ------------------------------------------------------------- Auslosung

  static TournamentPlan draw(
    TournamentFormat format,
    List<Participant> participants, {
    PlanOptions options = const PlanOptions(),
    Random? rng,
  }) {
    if (format == TournamentFormat.friendly) {
      throw ArgumentError('Freundschaftsspiele brauchen keine Auslosung');
    }
    if (participants.length < 2) throw ArgumentError('Mindestens 2 Teilnehmer nötig');
    if (participants.map((p) => p.id).toSet().length != participants.length) {
      throw ArgumentError('Teilnehmer-IDs müssen eindeutig sein');
    }
    final r = rng ?? Random();
    final plan = TournamentPlan._(
        format: format, participants: List.of(participants), options: options);
    switch (format) {
      case TournamentFormat.singleElimination:
      case TournamentFormat.doubleElimination:
        final pos = bracketPositions(participants, useSeeds: options.useSeeds, rng: r);
        plan.positions = [for (final p in pos) p?.id];
        plan._buildBracket();
        plan.phase = PlanPhase.knockout;
      case TournamentFormat.roundRobin:
      case TournamentFormat.league:
        plan.fixtures = RoundRobin.schedule(plan.ids,
            doubleRound: format == TournamentFormat.league || options.doubleRound, rng: r);
        plan.phase = PlanPhase.rounds;
      case TournamentFormat.groupsKnockout:
        final gc = options.groupCount;
        plan.groups = GroupStage.draw(participants,
            groupCount: gc, groupSize: gc == null ? options.groupSize : null, rng: r);
        plan.fixtures = GroupStage.fixtures(plan.groups, rng: r);
        plan.phase = PlanPhase.groups;
      case TournamentFormat.swiss:
        plan.swissTotalRounds =
            options.swissRounds ?? SwissSystem.recommendedRounds(participants.length);
        plan.phase = PlanPhase.rounds;
        plan._nextSwissRound(r);
      case TournamentFormat.friendly:
        break;
    }
    return plan;
  }

  void _buildBracket() {
    final byId = {for (final p in participants) p.id: p};
    final pos = [for (final id in positions) id == null ? null : byId[id]];
    bracket = format == TournamentFormat.doubleElimination
        ? Bracket.doubleElimination(pos)
        : Bracket.singleElimination(pos);
  }

  /// Tauscht zwei Positionen der Erstrundenauslosung (nur vor dem ersten Ergebnis).
  /// Gültig für K.-o.-Formate; bei Gruppen: [swapGroupMembers].
  void swapPositions(int i, int j) {
    if (bracket == null || phase != PlanPhase.knockout || format == TournamentFormat.groupsKnockout) {
      throw StateError('Positionen können nur im K.-o.-Baum getauscht werden');
    }
    if (hasResults) throw StateError('Auslosung nach erstem Ergebnis nicht mehr änderbar');
    final t = positions[i];
    positions[i] = positions[j];
    positions[j] = t;
    _buildBracket();
  }

  /// Tauscht zwei Spieler zwischen Gruppen (vor dem ersten Ergebnis).
  void swapGroupMembers(String playerA, String playerB) {
    if (format != TournamentFormat.groupsKnockout || phase != PlanPhase.groups) {
      throw StateError('Nur in der Gruppenphase möglich');
    }
    if (hasResults) throw StateError('Auslosung nach erstem Ergebnis nicht mehr änderbar');
    final ga = groups.indexWhere((g) => g.playerIds.contains(playerA));
    final gb = groups.indexWhere((g) => g.playerIds.contains(playerB));
    if (ga < 0 || gb < 0) throw ArgumentError('Spieler nicht gefunden');
    if (ga == gb) return;
    final newGroups = [
      for (var i = 0; i < groups.length; i++)
        Group(groups[i].name, [
          for (final id in groups[i].playerIds)
            if (i == ga && id == playerA)
              playerB
            else if (i == gb && id == playerB)
              playerA
            else
              id
        ])
    ];
    groups = newGroups;
    fixtures = GroupStage.fixtures(groups);
  }

  bool get hasResults =>
      (bracket?.matches.any((m) => m.winnerId != null && !m.isBye) ?? false) ||
      fixtures.any((f) => f.isPlayed);

  // ------------------------------------------------------------- Spielbetrieb

  String? _labelFor(String id) {
    final m = bracket?.matches.where((m) => m.id == id);
    if (m != null && m.isNotEmpty) {
      final x = m.first;
      return '${bracket!.roundLabel(x.side, x.round)} · Spiel ${x.index + 1}';
    }
    final f = fixtures.where((f) => f.id == id);
    if (f.isNotEmpty) {
      final x = f.first;
      final grp = x.group != null ? 'Gruppe ${groups[x.group!].name} · ' : '';
      return '$grp Runde ${x.round}'.trim();
    }
    return null;
  }

  /// Alle jetzt spielbaren Begegnungen.
  List<PlanMatch> get playable {
    final out = <PlanMatch>[];
    if (phase == PlanPhase.knockout && bracket != null) {
      for (final m in bracket!.playable) {
        out.add(PlanMatch(m.id, _labelFor(m.id)!, m.round, m.a.playerId!, m.b.playerId!));
      }
    }
    if (phase == PlanPhase.groups || phase == PlanPhase.rounds) {
      final open = fixtures.where((f) => !f.isPlayed).toList()
        ..sort((a, b) => a.round.compareTo(b.round));
      // Spielbar sind Begegnungen der frühesten offenen Runde zuerst; spätere
      // Runden ebenfalls (freie Reihenfolge im Liga-Betrieb), aber nach Runde sortiert.
      for (final f in open) {
        out.add(PlanMatch(f.id, _labelFor(f.id)!, f.round, f.homeId, f.awayId));
      }
    }
    return out;
  }

  /// Nächste Begegnung für [playerId].
  PlanMatch? nextMatchFor(String playerId) {
    for (final m in playable) {
      if (m.playerIds.contains(playerId)) return m;
    }
    return null;
  }

  /// Trägt ein Ergebnis ein und sorgt für den automatischen Fortschritt.
  void reportResult(String matchId, String winnerId, {int? legsA, int? legsB, Random? rng}) {
    final bm = bracket?.matches.where((m) => m.id == matchId);
    if (bm != null && bm.isNotEmpty) {
      bracket!.reportResult(matchId, winnerId, scoreA: legsA, scoreB: legsB);
      if (bracket!.isComplete) phase = PlanPhase.finished;
      return;
    }
    final idx = fixtures.indexWhere((f) => f.id == matchId);
    if (idx < 0) throw ArgumentError('Unbekannte Begegnung $matchId');
    final f = fixtures[idx];
    if (winnerId != f.homeId && winnerId != f.awayId) {
      throw ArgumentError('Sieger muss einer der beiden Spieler sein');
    }
    f.winnerId = winnerId;
    f.homeLegs = legsA;
    f.awayLegs = legsB;
    _afterFixtureResult(rng);
  }

  void _afterFixtureResult(Random? rng) {
    if (!fixtures.every((f) => f.isPlayed)) return;
    switch (format) {
      case TournamentFormat.groupsKnockout:
        if (phase == PlanPhase.groups) {
          final tables = GroupStage.standings(groups, fixtures,
              pointsPerWin: options.pointsPerWin, seedOrder: seedOrder);
          final q = GroupStage.qualifiers(tables, options.advancePerGroup);
          final pos = GroupStage.knockoutPositions(q, names);
          positions = [for (final p in pos) p?.id];
          bracket = Bracket.singleElimination(pos);
          phase = PlanPhase.knockout;
        }
      case TournamentFormat.swiss:
        if (swissRound < swissTotalRounds) {
          _nextSwissRound(rng ?? Random());
        } else {
          phase = PlanPhase.finished;
        }
      case TournamentFormat.roundRobin:
      case TournamentFormat.league:
        phase = PlanPhase.finished;
      default:
        break;
    }
  }

  void _nextSwissRound(Random rng) {
    final state = SwissSystem.buildState(ids, fixtures);
    final pairing = SwissSystem.pairRound(state, rng: rng);
    swissRound++;
    fixtures = [
      ...fixtures,
      for (var i = 0; i < pairing.pairs.length; i++)
        Fixture(
          id: 'swiss-$swissRound-$i',
          round: swissRound,
          homeId: pairing.pairs[i].$1,
          awayId: pairing.pairs[i].$2,
        ),
    ];
  }

  bool get isComplete => phase == PlanPhase.finished;

  /// Gesamtsieger (K.-o.: Baumsieger; Tabellenformate: Tabellenführer nach Abschluss).
  String? get championId {
    if (!isComplete) return null;
    if (bracket != null) return bracket!.championId;
    final t = tables();
    return t.isEmpty || t.first.isEmpty ? null : t.first.first.playerId;
  }

  /// Tabellen: je Gruppe eine (Gruppen), sonst eine Gesamttabelle.
  List<List<StandingsRow>> tables() {
    if (format == TournamentFormat.groupsKnockout) {
      return GroupStage.standings(groups, fixtures,
          pointsPerWin: options.pointsPerWin, seedOrder: seedOrder);
    }
    if (format == TournamentFormat.swiss) {
      return [SwissSystem.standings(ids, fixtures)];
    }
    if (format == TournamentFormat.roundRobin || format == TournamentFormat.league) {
      return [
        computeStandings(ids, fixtures,
            pointsPerWin: options.pointsPerWin, tiebreakOrder: seedOrder)
      ];
    }
    return const [];
  }

  // ----------------------------------------------------------- Serialisierung

  Map<String, dynamic> toJson() => {
        'format': format.name,
        'participants': participants.map((p) => p.toJson()).toList(),
        'options': {
          'useSeeds': options.useSeeds,
          'groupCount': options.groupCount,
          'groupSize': options.groupSize,
          'advancePerGroup': options.advancePerGroup,
          'swissRounds': options.swissRounds,
          'pointsPerWin': options.pointsPerWin,
          'doubleRound': options.doubleRound,
        },
        'bracket': bracket?.toJson(),
        'fixtures': fixtures.map((f) => f.toJson()).toList(),
        'groups': [
          for (final g in groups) {'name': g.name, 'playerIds': g.playerIds}
        ],
        'phase': phase.name,
        'swissRound': swissRound,
        'swissTotalRounds': swissTotalRounds,
        'positions': positions,
      };

  factory TournamentPlan.fromJson(Map<String, dynamic> j) {
    final o = Map<String, dynamic>.from(j['options'] as Map);
    return TournamentPlan._(
      format: TournamentFormat.values.byName(j['format'] as String),
      participants: [
        for (final p in j['participants'] as List)
          Participant.fromJson(Map<String, dynamic>.from(p as Map))
      ],
      options: PlanOptions(
        useSeeds: o['useSeeds'] as bool? ?? true,
        groupCount: (o['groupCount'] as num?)?.toInt(),
        groupSize: (o['groupSize'] as num?)?.toInt(),
        advancePerGroup: (o['advancePerGroup'] as num?)?.toInt() ?? 2,
        swissRounds: (o['swissRounds'] as num?)?.toInt(),
        pointsPerWin: (o['pointsPerWin'] as num?)?.toInt() ?? 2,
        doubleRound: o['doubleRound'] as bool? ?? false,
      ),
      bracket: j['bracket'] == null
          ? null
          : Bracket.fromJson(Map<String, dynamic>.from(j['bracket'] as Map)),
      fixtures: [
        for (final f in (j['fixtures'] as List? ?? []))
          Fixture.fromJson(Map<String, dynamic>.from(f as Map))
      ],
      groups: [
        for (final g in (j['groups'] as List? ?? []))
          Group((g as Map)['name'] as String, List<String>.from(g['playerIds'] as List))
      ],
      phase: PlanPhase.values.byName(j['phase'] as String),
      swissRound: (j['swissRound'] as num?)?.toInt() ?? 0,
      swissTotalRounds: (j['swissTotalRounds'] as num?)?.toInt() ?? 0,
      positions: List<String?>.from(j['positions'] as List? ?? const []),
    );
  }
}
