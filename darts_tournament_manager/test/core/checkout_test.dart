import 'package:darts_tournament_manager/core/checkout/checkout_calculator.dart';
import 'package:darts_tournament_manager/core/models/dart_throw.dart';
import 'package:darts_tournament_manager/core/models/rules.dart';
import 'package:darts_tournament_manager/core/x01/finish.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calc = CheckoutCalculator();

  // Tabelle aus der Anforderung (Double Out).
  const spec = {
    170: 'T20 – T20 – Bull',
    167: 'T20 – T19 – Bull',
    164: 'T20 – T18 – Bull',
    161: 'T20 – T17 – Bull',
    160: 'T20 – T20 – D20',
    141: 'T20 – T19 – D12',
    121: 'T20 – T11 – D14',
    100: 'T20 – D20',
    80: 'T20 – D10',
    64: 'T16 – D8',
    40: 'D20',
    32: 'D16',
    24: 'D12',
    16: 'D8',
    8: 'D4',
    2: 'D1',
  };

  test('Standard-Routen entsprechen der Vorgabetabelle', () {
    spec.forEach((score, route) {
      expect(calc.standardRoute(score).toString(), route, reason: 'Rest $score');
    });
  });

  test('50: Bull oder S10 - D20 sind beide gültig und vorgeschlagen', () {
    final all = calc.allRoutes(50).map((r) => r.toString()).toList();
    expect(all, contains('Bull'));
    expect(all, contains('S10 – D20'));
    expect(calc.standardRoute(50).toString(), 'Bull');
  });

  test('jede Route ist regelkonform (Summe, letzter Dart, kein Bust unterwegs)', () {
    for (final out in OutMode.values) {
      final c = CheckoutCalculator(outMode: out);
      for (var s = 1; s <= maxCheckout(out); s++) {
        final routes = c.allRoutes(s);
        expect(routes.isNotEmpty, canFinishWithin(s, 3, out), reason: '$out $s');
        for (final r in routes) {
          expect(r.total, s, reason: '$out $s $r');
          expect(isValidFinishDart(r.finisher, out), isTrue, reason: '$out $s $r');
          var rest = s;
          for (final d in r.darts.take(r.darts.length - 1)) {
            rest -= d.score;
            expect(rest >= minimumRemaining(out), isTrue, reason: '$out $s $r');
          }
          expect(r.darts.length <= 3, isTrue);
        }
      }
    }
  });

  test('Bogey-Zahlen haben bei Double Out keinen Weg', () {
    for (final s in [169, 168, 166, 165, 163, 162, 1, 171, 0, -5]) {
      expect(calc.allRoutes(s), isEmpty, reason: '$s');
      expect(calc.standardRoute(s), isNull);
    }
  });

  test('berücksichtigt verbleibende Darts', () {
    expect(calc.allRoutes(100, dartsLeft: 1), isEmpty);
    expect(calc.standardRoute(100, dartsLeft: 2).toString(), 'T20 – D20');
    expect(calc.standardRoute(170, dartsLeft: 2), isNull);
    expect(calc.standardRoute(170, dartsLeft: 3), isNotNull);
    // Mit nur einem Dart bleibt nur das direkte Finish
    expect(calc.standardRoute(32, dartsLeft: 1).toString(), 'D16');
    expect(calc.standardRoute(33, dartsLeft: 1), isNull);
  });

  test('Standard nutzt immer die minimale Dartzahl', () {
    for (var s = 2; s <= 170; s++) {
      final all = calc.allRoutes(s);
      if (all.isEmpty) continue;
      final min = all.map((r) => r.darts.length).reduce((a, b) => a < b ? a : b);
      expect(calc.standardRoute(s)!.darts.length, min, reason: '$s');
    }
  });

  test('Master Out und Single Out', () {
    const m = CheckoutCalculator(outMode: OutMode.master);
    expect(m.standardRoute(60).toString(), anyOf('T20', 'D30'.isEmpty ? '' : 'T20'));
    expect(m.allRoutes(57).map((r) => r.toString()), contains('T19'));
    expect(m.standardRoute(1), isNull);
    expect(m.standardRoute(180).toString(), 'T20 – T20 – T20');
    const s = CheckoutCalculator(outMode: OutMode.single);
    expect(s.standardRoute(1).toString(), 'S1');
    expect(s.standardRoute(60).toString(), 'T20');
  });

  test('Varianten: Lieblingsdoppel, sichere Route, Alternative ohne Duplikate', () {
    final sug = calc.suggestions(80, favoriteDouble: 16);
    final kinds = sug.map((s) => s.kind).toSet();
    expect(kinds, contains(CheckoutKind.standard));
    expect(kinds, contains(CheckoutKind.favoriteDouble));
    final fav = sug.firstWhere((s) => s.kind == CheckoutKind.favoriteDouble);
    expect(fav.route.finisher, DartThrow.double(16));
    final safe = sug.firstWhere((s) => s.kind == CheckoutKind.safe);
    expect(safe.route.darts.take(safe.route.darts.length - 1).every((d) => d.isSingle), isTrue);
    expect(sug.map((s) => s.route).toSet().length, sug.length, reason: 'keine Duplikate');
    expect(calc.suggestions(169), isEmpty);
  });

  test('Lieblingsdoppel nicht möglich -> keine Variante dafür', () {
    final sug = calc.suggestions(2, favoriteDouble: 16);
    expect(sug.any((s) => s.kind == CheckoutKind.favoriteDouble), isFalse);
  });
}
