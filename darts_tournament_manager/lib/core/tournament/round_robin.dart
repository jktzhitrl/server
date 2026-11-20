import 'dart:math';

import 'participant.dart';

/// Eine geplante Begegnung (Jeder-gegen-Jeden, Gruppe, Liga, Schweizer System).
class Fixture {
  final String id;
  final int round;
  final String homeId;
  final String awayId;

  /// Gruppen-Index bzw. `null`.
  final int? group;

  /// Ergebnis (Legs). `null` = noch nicht gespielt.
  int? homeLegs;
  int? awayLegs;
  String? winnerId;

  Fixture({
    required this.id,
    required this.round,
    required this.homeId,
    required this.awayId,
    this.group,
    this.homeLegs,
    this.awayLegs,
    this.winnerId,
  });

  bool get isPlayed => winnerId != null;
  List<String> get playerIds => [homeId, awayId];

  Map<String, dynamic> toJson() => {
        'id': id,
        'round': round,
        'homeId': homeId,
        'awayId': awayId,
        'group': group,
        'homeLegs': homeLegs,
        'awayLegs': awayLegs,
        'winnerId': winnerId,
      };

  factory Fixture.fromJson(Map<String, dynamic> j) => Fixture(
        id: j['id'] as String,
        round: (j['round'] as num).toInt(),
        homeId: j['homeId'] as String,
        awayId: j['awayId'] as String,
        group: (j['group'] as num?)?.toInt(),
        homeLegs: (j['homeLegs'] as num?)?.toInt(),
        awayLegs: (j['awayLegs'] as num?)?.toInt(),
        winnerId: j['winnerId'] as String?,
      );
}

/// Spielplan nach dem Kreisverfahren (Berger-Tabelle).
class RoundRobin {
  /// Erzeugt den Spielplan. Bei ungerader Teilnehmerzahl hat pro Runde ein
  /// Spieler spielfrei (Freilos). [doubleRound] = Hin- und Rückrunde (Liga).
  /// [shuffle] zufällige Auslosung der Reihenfolge.
  static List<Fixture> schedule(
    List<String> playerIds, {
    bool doubleRound = false,
    Random? rng,
    bool shuffle = true,
    int? group,
    String idPrefix = 'rr',
  }) {
    if (playerIds.length < 2) throw ArgumentError('Mindestens 2 Teilnehmer nötig');
    final ids = List<String>.from(playerIds);
    if (shuffle) ids.shuffle(rng ?? Random());
    final hasBye = ids.length.isOdd;
    if (hasBye) ids.add('\u0000bye');
    final n = ids.length;
    final rounds = n - 1;
    final firstHalf = <Fixture>[];
    var arr = List<String>.from(ids);
    for (var r = 0; r < rounds; r++) {
      for (var i = 0; i < n ~/ 2; i++) {
        var home = arr[i];
        var away = arr[n - 1 - i];
        if (home == '\u0000bye' || away == '\u0000bye') continue;
        // Heim/Auswärts abwechseln, damit niemand dauerhaft Heimvorteil hat.
        if (i == 0 && r.isOdd) {
          final t = home;
          home = away;
          away = t;
        }
        firstHalf.add(Fixture(
          id: '$idPrefix-${group ?? 0}-${r + 1}-$i',
          round: r + 1,
          homeId: home,
          awayId: away,
          group: group,
        ));
      }
      // Rotation: erstes Element fix.
      arr = [arr.first, arr.last, ...arr.sublist(1, arr.length - 1)];
    }
    if (!doubleRound) return firstHalf;
    final second = [
      for (final f in firstHalf)
        Fixture(
          id: '${f.id}-rueck',
          round: f.round + rounds,
          homeId: f.awayId,
          awayId: f.homeId,
          group: group,
        )
    ];
    return [...firstHalf, ...second];
  }

  /// Spielfreie Spieler pro Runde (nur bei ungerader Teilnehmerzahl).
  static Map<int, String> byes(List<Fixture> fixtures, List<String> playerIds) {
    final out = <int, String>{};
    final rounds = fixtures.map((f) => f.round).toSet();
    for (final r in rounds) {
      final playing = fixtures.where((f) => f.round == r).expand((f) => f.playerIds).toSet();
      final rest = playerIds.where((p) => !playing.contains(p)).toList();
      if (rest.length == 1) out[r] = rest.first;
    }
    return out;
  }
}

/// Zeile der Tabelle.
class StandingsRow {
  final String playerId;
  int played = 0;
  int wins = 0;
  int losses = 0;
  int legsFor = 0;
  int legsAgainst = 0;
  int points = 0;
  int rank = 0;

  /// Nur Schweizer System: Summe der Gegnerpunkte (Buchholz).
  int buchholz = 0;
  StandingsRow(this.playerId);

  int get legDiff => legsFor - legsAgainst;
}

/// Tabelle mit Tiebreakern: Punkte, Leg-Differenz, gewonnene Legs,
/// direkter Vergleich (bei genau zwei punktgleichen Spielern), danach [tiebreakOrder]
/// (z. B. Setzliste) bzw. die ID.
List<StandingsRow> computeStandings(
  List<String> playerIds,
  List<Fixture> fixtures, {
  int pointsPerWin = 2,
  int pointsPerLoss = 0,
  List<String>? tiebreakOrder,
}) {
  final rows = {for (final id in playerIds) id: StandingsRow(id)};
  for (final f in fixtures) {
    if (!f.isPlayed) continue;
    final h = rows[f.homeId], a = rows[f.awayId];
    if (h == null || a == null) continue;
    h.played++;
    a.played++;
    h.legsFor += f.homeLegs ?? 0;
    h.legsAgainst += f.awayLegs ?? 0;
    a.legsFor += f.awayLegs ?? 0;
    a.legsAgainst += f.homeLegs ?? 0;
    final homeWon = f.winnerId == f.homeId;
    final winner = homeWon ? h : a;
    final loser = homeWon ? a : h;
    winner.wins++;
    winner.points += pointsPerWin;
    loser.losses++;
    loser.points += pointsPerLoss;
  }

  int h2h(String x, String y) {
    // > 0, wenn x den direkten Vergleich gewonnen hat.
    var score = 0;
    for (final f in fixtures) {
      if (!f.isPlayed) continue;
      final pair = {f.homeId, f.awayId};
      if (!(pair.contains(x) && pair.contains(y))) continue;
      score += f.winnerId == x ? 1 : -1;
    }
    return score;
  }

  int order(String id) {
    final i = tiebreakOrder?.indexOf(id) ?? -1;
    return i < 0 ? 1 << 20 : i;
  }

  final list = rows.values.toList();
  list.sort((x, y) {
    var c = y.points.compareTo(x.points);
    if (c != 0) return c;
    c = y.legDiff.compareTo(x.legDiff);
    if (c != 0) return c;
    c = y.legsFor.compareTo(x.legsFor);
    if (c != 0) return c;
    final tied = list
        .where((r) =>
            r.points == x.points && r.legDiff == x.legDiff && r.legsFor == x.legsFor)
        .length;
    if (tied == 2) {
      c = -h2h(x.playerId, y.playerId).compareTo(0);
      if (c != 0) return c;
    }
    c = order(x.playerId).compareTo(order(y.playerId));
    return c != 0 ? c : x.playerId.compareTo(y.playerId);
  });
  for (var i = 0; i < list.length; i++) {
    list[i].rank = i + 1;
  }
  return list;
}

/// Hilfsfunktion: Teilnehmer-Namen für Anzeige.
Map<String, String> nameMap(List<Participant> ps) => {for (final p in ps) p.id: p.name};
