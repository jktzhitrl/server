import 'dart:math';

import 'participant.dart';
import 'round_robin.dart';
import 'seeding.dart';

class Group {
  final String name;
  final List<String> playerIds;
  const Group(this.name, this.playerIds);
}

class Qualifier {
  final String playerId;
  final int group;
  final int rankInGroup; // 1-basiert
  const Qualifier(this.playerId, this.group, this.rankInGroup);
}

/// Gruppenphase mit anschließender K.-o.-Runde.
class GroupStage {
  /// Verteilt die Teilnehmer auf Gruppen. Entweder [groupCount] oder
  /// [groupSize] angeben. Gesetzte Spieler werden "snake" verteilt, damit
  /// sich Top-Gesetzte nicht in derselben Gruppe treffen; die Gruppen sind
  /// höchstens um einen Spieler verschieden groß.
  static List<Group> draw(
    List<Participant> participants, {
    int? groupCount,
    int? groupSize,
    Random? rng,
  }) {
    if ((groupCount == null) == (groupSize == null)) {
      throw ArgumentError('Entweder groupCount oder groupSize angeben');
    }
    final n = participants.length;
    final g = groupCount ?? ((n + groupSize! - 1) ~/ groupSize);
    if (g < 1 || n < g * 2 - (g > 1 ? 0 : 0) || n < 2) {
      throw ArgumentError('Zu wenige Teilnehmer für $g Gruppen');
    }
    final ranked = rankParticipants(participants, rng ?? Random());
    final groups = List.generate(g, (_) => <String>[]);
    // Snake: 0..g-1, g-1..0, ...
    for (var i = 0; i < ranked.length; i++) {
      final lap = i ~/ g;
      final pos = i % g;
      final gi = lap.isEven ? pos : g - 1 - pos;
      groups[gi].add(ranked[i].id);
    }
    return [
      for (var i = 0; i < g; i++) Group(String.fromCharCode(65 + i), groups[i]),
    ];
  }

  /// Spielplan aller Gruppen.
  static List<Fixture> fixtures(List<Group> groups,
      {bool doubleRound = false, Random? rng, bool shuffle = true}) {
    return [
      for (var gi = 0; gi < groups.length; gi++)
        ...RoundRobin.schedule(groups[gi].playerIds,
            doubleRound: doubleRound, rng: rng, shuffle: shuffle, group: gi, idPrefix: 'grp'),
    ];
  }

  /// Gruppentabellen.
  static List<List<StandingsRow>> standings(List<Group> groups, List<Fixture> fixtures,
      {int pointsPerWin = 2, List<String>? seedOrder}) {
    return [
      for (var gi = 0; gi < groups.length; gi++)
        computeStandings(
          groups[gi].playerIds,
          fixtures.where((f) => f.group == gi).toList(),
          pointsPerWin: pointsPerWin,
          tiebreakOrder: seedOrder,
        ),
    ];
  }

  /// Sind alle Gruppenspiele gespielt?
  static bool isComplete(List<Fixture> fixtures) => fixtures.every((f) => f.isPlayed);

  /// Qualifikanten (die besten [advance] jeder Gruppe).
  static List<Qualifier> qualifiers(List<List<StandingsRow>> tables, int advance) => [
        for (var gi = 0; gi < tables.length; gi++)
          for (final row in tables[gi].take(advance)) Qualifier(row.playerId, gi, row.rank),
      ];

  /// Positionsliste für den K.-o.-Baum: Gruppensieger werden gesetzt, Gruppenzweite
  /// gegen fremde Gruppen gelost; Spieler derselben Gruppe treffen sich nach
  /// Möglichkeit erst später.
  static List<Participant?> knockoutPositions(
    List<Qualifier> qualifiers,
    Map<String, String> names,
  ) {
    final q = [...qualifiers]
      ..sort((a, b) {
        final c = a.rankInGroup.compareTo(b.rankInGroup);
        if (c != 0) return c;
        // Bei gleichem Rang: Rang 1 aufsteigend nach Gruppe, danach paarweise getauscht.
        final ga = a.rankInGroup.isOdd ? a.group : (a.group ^ 1);
        final gb = b.rankInGroup.isOdd ? b.group : (b.group ^ 1);
        return ga.compareTo(gb);
      });
    final size = nextPowerOfTwo(q.length);
    final order = seedOrder(size);
    // positions[i] = Qualifier oder null
    final pos = [for (final s in order) s <= q.length ? q[s - 1] : null];

    bool clash(int pair) {
      final x = pos[2 * pair], y = pos[2 * pair + 1];
      return x != null && y != null && x.group == y.group;
    }

    final pairs = size ~/ 2;
    for (var p = 0; p < pairs; p++) {
      if (!clash(p)) continue;
      for (var o = 0; o < pairs; o++) {
        if (o == p) continue;
        // Tausche den zweiten Spieler des Paares p mit dem zweiten von o.
        final a = pos[2 * p + 1];
        pos[2 * p + 1] = pos[2 * o + 1];
        pos[2 * o + 1] = a;
        if (!clash(p) && !clash(o)) break;
        // zurücktauschen
        final b = pos[2 * p + 1];
        pos[2 * p + 1] = pos[2 * o + 1];
        pos[2 * o + 1] = b;
      }
    }
    return [
      for (final e in pos)
        e == null ? null : Participant(id: e.playerId, name: names[e.playerId] ?? e.playerId)
    ];
  }
}
