import '../models/dart_throw.dart';
import '../models/rules.dart';
import '../x01/finish.dart';
import '../x01/visit.dart';

/// Ein abgeschlossenes oder laufendes Leg aus Sicht der Statistik.
class LegRecord {
  final int legNo;
  final List<Visit> visits;

  /// Spieler-ID je Index im Match.
  final List<String> playerIds;
  final String? winnerId;
  final OutMode outMode;
  final InMode inMode;
  const LegRecord({
    required this.legNo,
    required this.visits,
    required this.playerIds,
    required this.winnerId,
    this.outMode = OutMode.double,
    this.inMode = InMode.straight,
  });
}

/// Zusammenfassung eines Matches für Siege/Niederlagen und Sätze.
class MatchSummary {
  final String matchId;
  final List<String> playerIds;
  final String? winnerId;
  final Map<String, int> setsWon;
  final DateTime? playedAt;
  const MatchSummary({
    required this.matchId,
    required this.playerIds,
    required this.winnerId,
    this.setsWon = const {},
    this.playedAt,
  });
}

/// Trefferquote eines einzelnen Doppelfelds.
class DoubleFieldStat {
  final int attempts;
  final int hits;
  const DoubleFieldStat(this.attempts, this.hits);
  double get rate => attempts == 0 ? 0 : hits / attempts;
}

/// Statistik eines Spielers. Felder, die nur mit Einzeldart-Daten berechenbar
/// sind, sind `null`, wenn dafür keine Daten vorliegen ("nicht verfügbar").
class PlayerStats {
  final String playerId;
  final int legsPlayed;
  final int legsWon;
  final int legsLost;
  final int setsWon;
  final int matchesWon;
  final int matchesLost;
  final int totalScore;
  final int dartsThrown;
  final int visitCount;
  final double? threeDartAverage;
  final double? first9Average;
  final int count180;
  final int count140Plus;
  final int count100Plus;
  final int highestVisit;
  final int? highestCheckout;
  final double? averageCheckout;
  final int checkoutAttempts;
  final int checkoutHits;

  /// Checkout-Quote (0..1); `null`, wenn keine Versuche bekannt sind.
  final double? checkoutRate;

  /// Anzahl Checkouts, deren Versuchszahl unbekannt war (Modus B ohne Angabe).
  final int checkoutsWithUnknownAttempts;

  /// Beste Leg = wenigste Darts in einem gewonnenen Leg.
  final int? bestLegDarts;

  /// Schlechtestes gewonnenes Leg = meiste Darts.
  final int? worstLegDarts;

  /// Gab es Einzeldart-Daten (Modus A)? Wenn nicht, sind Doppelfeld-Statistiken nicht verfügbar.
  final bool hasDartData;

  /// Trefferquote je Doppelfeld (Schlüssel 1..20, 25 = Bull); `null` ohne Dart-Daten.
  final Map<int, DoubleFieldStat>? doubleStats;

  const PlayerStats({
    required this.playerId,
    required this.legsPlayed,
    required this.legsWon,
    required this.legsLost,
    required this.setsWon,
    required this.matchesWon,
    required this.matchesLost,
    required this.totalScore,
    required this.dartsThrown,
    required this.visitCount,
    required this.threeDartAverage,
    required this.first9Average,
    required this.count180,
    required this.count140Plus,
    required this.count100Plus,
    required this.highestVisit,
    required this.highestCheckout,
    required this.averageCheckout,
    required this.checkoutAttempts,
    required this.checkoutHits,
    required this.checkoutRate,
    required this.checkoutsWithUnknownAttempts,
    required this.bestLegDarts,
    required this.worstLegDarts,
    required this.hasDartData,
    required this.doubleStats,
  });

  /// Bevorzugte Doppel (nach Versuchen absteigend), nur mit Dart-Daten.
  List<int>? get preferredDoubles {
    final s = doubleStats;
    if (s == null) return null;
    final keys = s.keys.toList()
      ..sort((a, b) {
        final c = s[b]!.attempts.compareTo(s[a]!.attempts);
        return c != 0 ? c : a.compareTo(b);
      });
    return keys;
  }

  /// Bestes Doppel nach Trefferquote (min. [minAttempts] Versuche).
  int? bestDouble({int minAttempts = 3}) {
    final s = doubleStats;
    if (s == null) return null;
    int? best;
    double bestRate = -1;
    s.forEach((k, v) {
      if (v.attempts >= minAttempts && v.rate > bestRate) {
        best = k;
        bestRate = v.rate;
      }
    });
    return best;
  }
}

/// Berechnet die Statistik des Spielers [playerId] aus Legs und Matches.
///
/// Konventionen:
///  * 3-Dart-Average = Punkte / gezählte Darts * 3 (Bust-Aufnahmen zählen 0
///    Punkte und 3 Darts).
///  * "100+" / "140+" sind kumulativ (180er zählen mit), `count180` separat.
///  * First-9 = die ersten drei Aufnahmen (9 Darts) jedes Legs.
///  * Checkout-Quote = Treffer / Versuche über alle Aufnahmen mit bekannter
///    Versuchszahl. Checkouts ohne bekannte Versuche gehen nicht in die Quote ein.
PlayerStats computePlayerStats(
  String playerId,
  List<LegRecord> legs, {
  List<MatchSummary> matches = const [],
}) {
  var legsPlayed = 0, legsWon = 0, legsLost = 0;
  var totalScore = 0, darts = 0, visitCount = 0;
  var c180 = 0, c140 = 0, c100 = 0, highest = 0;
  int? highestCo;
  var coSum = 0, coCount = 0;
  var attempts = 0, hits = 0, unknownCo = 0;
  var f9Points = 0, f9Darts = 0;
  int? bestLeg, worstLeg;
  var hasDartData = false;
  final dbl = <int, List<int>>{}; // field -> [attempts, hits]

  for (final leg in legs) {
    final idx = leg.playerIds.indexOf(playerId);
    if (idx < 0) continue;
    final mine = leg.visits.where((v) => v.playerIndex == idx).toList()
      ..sort((a, b) => a.visitNo.compareTo(b.visitNo));
    if (mine.isEmpty && leg.winnerId == null) continue;
    legsPlayed++;
    if (leg.winnerId == playerId) {
      legsWon++;
    } else if (leg.winnerId != null) {
      legsLost++;
    }
    var legDarts = 0;
    for (var i = 0; i < mine.length; i++) {
      final v = mine[i];
      visitCount++;
      totalScore += v.points;
      darts += v.dartsThrown;
      legDarts += v.dartsThrown;
      if (i < 3) {
        f9Points += v.points;
        f9Darts += v.dartsThrown;
      }
      if (!v.bust) {
        if (v.points > highest) highest = v.points;
        if (v.points == 180) c180++;
        if (v.points >= 140) c140++;
        if (v.points >= 100) c100++;
      }
      if (v.checkout) {
        highestCo = (highestCo == null || v.points > highestCo) ? v.points : highestCo;
        coSum += v.points;
        coCount++;
        if (v.checkoutAttempts == null) unknownCo++;
      }
      if (v.checkoutAttempts != null) {
        attempts += v.checkoutAttempts!;
        if (v.checkout) hits++;
      }
      if (v.darts != null) {
        hasDartData = true;
        _collectDoubleStats(v, leg, dbl);
      }
    }
    if (leg.winnerId == playerId && legDarts > 0) {
      bestLeg = bestLeg == null || legDarts < bestLeg ? legDarts : bestLeg;
      worstLeg = worstLeg == null || legDarts > worstLeg ? legDarts : worstLeg;
    }
  }

  var matchesWon = 0, matchesLost = 0, setsWon = 0;
  for (final m in matches) {
    if (!m.playerIds.contains(playerId)) continue;
    setsWon += m.setsWon[playerId] ?? 0;
    if (m.winnerId == playerId) {
      matchesWon++;
    } else if (m.winnerId != null) {
      matchesLost++;
    }
  }

  return PlayerStats(
    playerId: playerId,
    legsPlayed: legsPlayed,
    legsWon: legsWon,
    legsLost: legsLost,
    setsWon: setsWon,
    matchesWon: matchesWon,
    matchesLost: matchesLost,
    totalScore: totalScore,
    dartsThrown: darts,
    visitCount: visitCount,
    threeDartAverage: darts == 0 ? null : totalScore / darts * 3,
    first9Average: f9Darts == 0 ? null : f9Points / f9Darts * 3,
    count180: c180,
    count140Plus: c140,
    count100Plus: c100,
    highestVisit: highest,
    highestCheckout: highestCo,
    averageCheckout: coCount == 0 ? null : coSum / coCount,
    checkoutAttempts: attempts,
    checkoutHits: hits,
    checkoutRate: attempts == 0 ? null : hits / attempts,
    checkoutsWithUnknownAttempts: unknownCo,
    bestLegDarts: bestLeg,
    worstLegDarts: worstLeg,
    hasDartData: hasDartData,
    doubleStats: hasDartData
        ? {for (final e in dbl.entries) e.key: DoubleFieldStat(e.value[0], e.value[1])}
        : null,
  );
}

void _collectDoubleStats(Visit v, LegRecord leg, Map<int, List<int>> out) {
  var cur = v.startScore;
  for (final d in v.darts!) {
    final isFinishable = isOneDartFinish(cur, leg.outMode);
    final next = cur - d.score;
    if (isFinishable) {
      final target = finishTargetFor(cur, leg.outMode)!;
      final key = target.number;
      final e = out.putIfAbsent(key, () => [0, 0]);
      e[0]++;
      if (next == 0 && isValidFinishDart(d, leg.outMode)) e[1]++;
    }
    if (next <= 0 || next < minimumRemaining(leg.outMode)) break;
    cur = next;
  }
}

/// Fasst mehrere Legs eines Spielers zu "Dart-Verteilung" zusammen (nur Modus A).
Map<String, int>? dartDistribution(String playerId, List<LegRecord> legs) {
  final out = <String, int>{'S': 0, 'D': 0, 'T': 0, 'Miss': 0, 'Bull': 0};
  var any = false;
  for (final leg in legs) {
    final idx = leg.playerIds.indexOf(playerId);
    if (idx < 0) continue;
    for (final v in leg.visits.where((v) => v.playerIndex == idx && v.darts != null)) {
      any = true;
      for (final DartThrow d in v.darts!) {
        if (d.isMiss) {
          out['Miss'] = out['Miss']! + 1;
        } else if (d.isBull && d.isDouble) {
          out['Bull'] = out['Bull']! + 1;
        } else {
          final k = d.isDouble ? 'D' : d.isTriple ? 'T' : 'S';
          out[k] = out[k]! + 1;
        }
      }
    }
  }
  return any ? out : null;
}
