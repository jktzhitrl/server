import 'dart:math';

import 'round_robin.dart';

/// Stand eines Spielers im Schweizer System.
class SwissPlayer {
  final String id;
  int points;
  final Set<String> opponents;
  bool hadBye;
  SwissPlayer(this.id, {this.points = 0, Set<String>? opponents, this.hadBye = false})
      : opponents = opponents ?? <String>{};
}

class SwissPairing {
  final List<(String, String)> pairs;
  final String? bye;
  const SwissPairing(this.pairs, this.bye);
}

/// Schweizer System: Paarung nach Punktestand, keine Rückspiele, Freilos für
/// den Schlechtplatziertesten, der noch keins hatte.
class SwissSystem {
  /// Empfohlene Rundenzahl: ceil(log2(n)).
  static int recommendedRounds(int n) {
    var r = 0;
    while ((1 << r) < n) {
      r++;
    }
    return r < 1 ? 1 : r;
  }

  /// Baut den Spielerstand aus bisherigen Fixtures (Freilose = Runde ohne Fixture).
  static List<SwissPlayer> buildState(List<String> ids, List<Fixture> played, {int rounds = 0}) {
    final map = {for (final id in ids) id: SwissPlayer(id)};
    for (final f in played) {
      final h = map[f.homeId], a = map[f.awayId];
      if (h == null || a == null) continue;
      h.opponents.add(a.id);
      a.opponents.add(h.id);
      if (f.isPlayed) {
        (f.winnerId == f.homeId ? h : a).points += 1;
      }
    }
    // Freilose ermitteln
    final byRound = <int, Set<String>>{};
    for (final f in played) {
      byRound.putIfAbsent(f.round, () => {}).addAll(f.playerIds);
    }
    byRound.forEach((r, playing) {
      for (final id in ids) {
        if (!playing.contains(id)) {
          map[id]!.hadBye = true;
          map[id]!.points += 1; // Freilos zählt als Sieg
        }
      }
    });
    return map.values.toList();
  }

  /// Berechnet die Paarungen der nächsten Runde.
  static SwissPairing pairRound(List<SwissPlayer> players, {Random? rng}) {
    final r = rng ?? Random();
    final sorted = List<SwissPlayer>.from(players)..shuffle(r);
    sorted.sort((a, b) => b.points.compareTo(a.points));
    String? bye;
    final pool = List<SwissPlayer>.from(sorted);
    if (pool.length.isOdd) {
      // Freilos: niedrigster Spieler ohne bisheriges Freilos.
      final candidate = pool.reversed.firstWhere((p) => !p.hadBye, orElse: () => pool.last);
      pool.remove(candidate);
      bye = candidate.id;
    }
    final result = _pairBacktrack(pool, true) ?? _pairBacktrack(pool, false)!;
    return SwissPairing(result, bye);
  }

  static List<(String, String)>? _pairBacktrack(List<SwissPlayer> pool, bool avoidRematch) {
    if (pool.isEmpty) return [];
    final first = pool.first;
    for (var i = 1; i < pool.length; i++) {
      final other = pool[i];
      if (avoidRematch && first.opponents.contains(other.id)) continue;
      final rest = [...pool.sublist(1, i), ...pool.sublist(i + 1)];
      final sub = _pairBacktrack(rest, avoidRematch);
      if (sub != null) return [(first.id, other.id), ...sub];
    }
    return null;
  }

  /// Tabelle mit Buchholz-Feinwertung.
  static List<StandingsRow> standings(List<String> ids, List<Fixture> fixtures) {
    final rows = computeStandings(ids, fixtures, pointsPerWin: 1);
    final byId = {for (final r in rows) r.playerId: r};
    final opp = <String, Set<String>>{};
    for (final f in fixtures) {
      opp.putIfAbsent(f.homeId, () => {}).add(f.awayId);
      opp.putIfAbsent(f.awayId, () => {}).add(f.homeId);
    }
    for (final r in rows) {
      r.buchholz = (opp[r.playerId] ?? {}).fold(0, (a, o) => a + (byId[o]?.points ?? 0));
    }
    rows.sort((x, y) {
      var c = y.points.compareTo(x.points);
      if (c != 0) return c;
      c = y.buchholz.compareTo(x.buchholz);
      if (c != 0) return c;
      c = y.legDiff.compareTo(x.legDiff);
      return c != 0 ? c : x.playerId.compareTo(y.playerId);
    });
    for (var i = 0; i < rows.length; i++) {
      rows[i].rank = i + 1;
    }
    return rows;
  }
}
