import 'package:darts_tournament_manager/core/models/dart_throw.dart';
import 'package:darts_tournament_manager/core/models/rules.dart';
import 'package:darts_tournament_manager/core/stats/player_stats.dart';
import 'package:darts_tournament_manager/core/x01/visit.dart';
import 'package:darts_tournament_manager/core/x01/x01_match.dart';
import 'package:flutter_test/flutter_test.dart';

DartThrow d(String s) => DartThrow.parse(s);

List<LegRecord> legsOf(X01Match m) {
  final byLeg = <int, List<dynamic>>{};
  for (final v in m.visits) {
    byLeg.putIfAbsent(v.legNo, () => []).add(v);
  }
  return [
    for (final e in byLeg.entries)
      LegRecord(
        legNo: e.key,
        visits: e.value.cast(),
        playerIds: m.playerIds,
        winnerId: m.state.legResults
            .where((r) => r.legNo == e.key)
            .map((r) => m.playerIds[r.winnerIndex])
            .firstOrNull,
        outMode: m.rules.outMode,
      )
  ];
}

void main() {
  X01Match start({int score = 170}) => X01Match(
        rules: X01Rules(startScore: score, format: const MatchFormat(legsToWinSet: 1)),
        playerIds: const ['a', 'b'],
      );

  test('Average, 180er, Checkout, Quote (Modus A)', () {
    var m = start(score: 301);
    m = m.submitDarts([d('T20'), d('T20'), d('T20')]); // a: 121 Rest, 180
    m = m.submitDarts([d('S20'), d('S5'), d('S1')]); // b: 26
    m = m.submitDarts([d('T20'), d('T11'), d('D14')]); // a: checkout 121 mit 3
    expect(m.isFinished, isTrue);
    final legs = legsOf(m);
    final a = computePlayerStats('a', legs);
    expect(a.count180, 1);
    expect(a.highestVisit, 180);
    expect(a.highestCheckout, 121);
    expect(a.dartsThrown, 6);
    expect(a.totalScore, 301);
    expect(a.threeDartAverage, closeTo(301 / 6 * 3, 1e-9));
    expect(a.first9Average, closeTo(301 / 6 * 3, 1e-9));
    expect(a.legsWon, 1);
    expect(a.legsLost, 0);
    expect(a.bestLegDarts, 6);
    // Checkout-Versuche: nur der letzte Dart (D14 bei Rest 28)
    expect(a.checkoutAttempts, 1);
    expect(a.checkoutHits, 1);
    expect(a.checkoutRate, 1.0);
    expect(a.hasDartData, isTrue);
    expect(a.doubleStats![14]!.hits, 1);
    final b = computePlayerStats('b', legs);
    expect(b.legsLost, 1);
    expect(b.checkoutRate, isNull);
    expect(b.highestCheckout, isNull);
  });

  test('Modus B: Dart-abhängige Statistiken sind nicht verfügbar', () {
    var m = start(score: 100);
    m = m.submitTotal(60).submitTotal(26).submitTotal(40, dartsUsed: 2, checkoutAttempts: 2);
    final legs = legsOf(m);
    final a = computePlayerStats('a', legs);
    expect(a.hasDartData, isFalse);
    expect(a.doubleStats, isNull);
    expect(a.preferredDoubles, isNull);
    expect(a.bestDouble(), isNull);
    expect(dartDistribution('a', legs), isNull);
    // aber Average und Checkout-Quote stehen zur Verfügung
    expect(a.threeDartAverage, closeTo(100 / 5 * 3, 1e-9));
    expect(a.checkoutAttempts, 2);
    expect(a.checkoutRate, 0.5);
  });

  test('Checkout ohne bekannte Versuche geht nicht in die Quote ein', () {
    var m = start(score: 100);
    m = m.submitTotal(60).submitTotal(26).submitTotal(40, dartsUsed: 2);
    final a = computePlayerStats('a', legsOf(m));
    expect(a.checkoutRate, isNull);
    expect(a.checkoutsWithUnknownAttempts, 1);
    expect(a.highestCheckout, 40);
    expect(a.averageCheckout, 40);
  });

  test('Bust zählt 0 Punkte und 3 Darts', () {
    var m = start(score: 100);
    m = m.submitTotal(140); // Bust (> Rest)
    m = m.submitTotal(0);
    final a = computePlayerStats('a', legsOf(m));
    expect(a.totalScore, 0);
    expect(a.dartsThrown, 3);
    expect(a.highestVisit, 0);
    expect(a.count140Plus, 0, reason: 'Bust-Aufnahme zählt nicht als 140+');
  });

  test('100+, 140+ kumulativ, First 9 nur erste drei Aufnahmen', () {
    final m0 = X01Match(
      rules: const X01Rules(startScore: 1001, format: MatchFormat(legsToWinSet: 1)),
      playerIds: const ['a', 'b'],
    );
    var m = m0;
    for (final t in [180, 100, 140, 60, 60]) {
      m = m.submitTotal(t).submitTotal(0);
    }
    final a = computePlayerStats('a', legsOf(m));
    expect(a.count180, 1);
    expect(a.count140Plus, 2);
    expect(a.count100Plus, 3);
    expect(a.first9Average, closeTo((180 + 100 + 140) / 9 * 3, 1e-9));
    expect(a.threeDartAverage, closeTo(540 / 15 * 3, 1e-9));
  });

  test('Matches: Siege/Niederlagen und Sätze', () {
    final stats = computePlayerStats('a', const [], matches: [
      const MatchSummary(
          matchId: '1', playerIds: ['a', 'b'], winnerId: 'a', setsWon: {'a': 2, 'b': 1}),
      const MatchSummary(
          matchId: '2', playerIds: ['a', 'c'], winnerId: 'c', setsWon: {'a': 0, 'c': 2}),
      const MatchSummary(matchId: '3', playerIds: ['b', 'c'], winnerId: 'b'),
    ]);
    expect(stats.matchesWon, 1);
    expect(stats.matchesLost, 1);
    expect(stats.setsWon, 2);
    expect(stats.threeDartAverage, isNull);
  });

  test('Bestes und schlechtestes Leg', () {
    final legs = [
      LegRecord(legNo: 1, playerIds: const ['a', 'b'], winnerId: 'a', visits: _fake('a', 3)),
      LegRecord(legNo: 2, playerIds: const ['a', 'b'], winnerId: 'a', visits: _fake('a', 5)),
      LegRecord(legNo: 3, playerIds: const ['a', 'b'], winnerId: 'b', visits: _fake('a', 9)),
    ];
    final s = computePlayerStats('a', legs);
    expect(s.bestLegDarts, 9);
    expect(s.worstLegDarts, 15);
  });
}

List<Visit> _fake(String id, int visits) => [
      for (var i = 0; i < visits; i++)
        Visit(
          id: 'v$i',
          playerIndex: 0,
          legNo: 1,
          visitNo: i + 1,
          startScore: 501,
          scoreAfter: 501,
          enteredTotal: 0,
          points: 0,
          bust: false,
          checkout: false,
          darts: null,
          dartsThrown: 3,
          checkoutAttempts: null,
          mode: InputMode.total,
          timestamp: DateTime.utc(2024),
        ),
    ];
