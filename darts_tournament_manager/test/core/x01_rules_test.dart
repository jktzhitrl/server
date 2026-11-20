import 'package:darts_tournament_manager/core/models/dart_throw.dart';
import 'package:darts_tournament_manager/core/models/rules.dart';
import 'package:darts_tournament_manager/core/x01/finish.dart';
import 'package:darts_tournament_manager/core/x01/visit.dart';
import 'package:flutter_test/flutter_test.dart';

DartThrow d(String s) => DartThrow.parse(s);

void main() {
  group('DartThrow', () {
    test('Punktwerte', () {
      expect(d('T20').score, 60);
      expect(d('D20').score, 40);
      expect(d('S20').score, 20);
      expect(d('T19').score, 57);
      expect(d('D16').score, 32);
      expect(d('S5').score, 5);
      expect(DartThrow.miss.score, 0);
      expect(DartThrow.outerBull.score, 25);
      expect(DartThrow.bullseye.score, 50);
    });
    test('ungültige Würfe', () {
      expect(() => DartThrow(3, 25), throwsArgumentError);
      expect(() => DartThrow(1, 21), throwsArgumentError);
      expect(() => DartThrow(4, 5), throwsArgumentError);
      expect(() => DartThrow.parse('X5'), throwsFormatException);
    });
    test('JSON-Roundtrip und 62 Treffer', () {
      for (final t in DartThrow.allScoring) {
        expect(DartThrow.fromJson(t.toJson()), t);
      }
      expect(DartThrow.allScoring.length, 62);
    });
  });

  const dout = X01Rules(outMode: OutMode.double);
  const sout = X01Rules(outMode: OutMode.single);
  const mout = X01Rules(outMode: OutMode.master);

  group('Finish-Darts', () {
    test('Double Out: nur Doppel inkl. Bullseye', () {
      expect(isValidFinishDart(d('D20'), OutMode.double), isTrue);
      expect(isValidFinishDart(d('Bull'), OutMode.double), isTrue);
      expect(isValidFinishDart(d('T20'), OutMode.double), isFalse);
      expect(isValidFinishDart(d('S20'), OutMode.double), isFalse);
      expect(isValidFinishDart(d('25'), OutMode.double), isFalse);
      expect(isValidFinishDart(DartThrow.miss, OutMode.double), isFalse);
    });
    test('Master Out: Doppel oder Triple', () {
      expect(isValidFinishDart(d('T20'), OutMode.master), isTrue);
      expect(isValidFinishDart(d('D1'), OutMode.master), isTrue);
      expect(isValidFinishDart(d('S20'), OutMode.master), isFalse);
      expect(isValidFinishDart(d('25'), OutMode.master), isFalse);
    });
    test('Single Out: jeder Treffer', () {
      expect(isValidFinishDart(d('S1'), OutMode.single), isTrue);
      expect(isValidFinishDart(d('25'), OutMode.single), isTrue);
      expect(isValidFinishDart(DartThrow.miss, OutMode.single), isFalse);
    });
    test('Ein-Dart-Finish', () {
      for (final s in [2, 4, 40, 50]) {
        expect(isOneDartFinish(s, OutMode.double), isTrue, reason: '$s');
      }
      for (final s in [1, 3, 41, 42 + 1, 60, 49]) {
        expect(isOneDartFinish(s, OutMode.double), isFalse, reason: '$s');
      }
      expect(isOneDartFinish(60, OutMode.master), isTrue);
      expect(isOneDartFinish(57, OutMode.master), isTrue);
      expect(isOneDartFinish(59, OutMode.master), isFalse);
      expect(isOneDartFinish(25, OutMode.single), isTrue);
    });
    test('Checkout-Grenzen (Double Out)', () {
      expect(canFinishWithin(170, 3, OutMode.double), isTrue);
      expect(canFinishWithin(171, 3, OutMode.double), isFalse);
      for (final bogey in [169, 168, 166, 165, 163, 162]) {
        expect(canFinishWithin(bogey, 3, OutMode.double), isFalse, reason: '$bogey');
      }
      expect(canFinishWithin(1, 3, OutMode.double), isFalse);
      expect(canFinishWithin(3, 3, OutMode.double), isTrue); // S1 + D1
      expect(canFinishWithin(100, 1, OutMode.double), isFalse);
      expect(canFinishWithin(100, 2, OutMode.double), isTrue);
      expect(canFinishWithin(180, 3, OutMode.master), isTrue);
      expect(canFinishWithin(1, 3, OutMode.single), isTrue);
    });
    test('erreichbare Summen', () {
      expect(isReachableTotal(180, 3), isTrue);
      expect(isReachableTotal(179, 3), isFalse);
      expect(isReachableTotal(163, 3), isFalse);
      expect(isReachableTotal(61, 1), isFalse);
      expect(isReachableTotal(0, 3), isTrue);
      expect(isReachableTotal(120, 2), isTrue);
    });
  });

  group('Modus A (Einzeldarts)', () {
    test('normale Aufnahme', () {
      final ev = evaluateDarts(
          remaining: 501, opened: true, darts: [d('T20'), d('T20'), d('T20')], rules: dout);
      expect(ev.outcome, VisitOutcome.normal);
      expect(ev.scoreAfter, 321);
      expect(ev.points, 180);
    });
    test('Bust: über den Rest', () {
      final ev = evaluateDarts(
          remaining: 40, opened: true, darts: [d('T20')], rules: dout);
      expect(ev.isBust, isTrue);
      expect(ev.scoreAfter, 40);
      expect(ev.points, 0);
      expect(ev.dartsCounted, 3);
    });
    test('Bust: Rest 1 bei Double Out', () {
      final ev =
          evaluateDarts(remaining: 33, opened: true, darts: [d('S16'), d('S16')], rules: dout);
      expect(ev.isBust, isTrue); // 33-32 = 1
      expect(
          evaluateDarts(
              remaining: 33,
              opened: true,
              darts: [d('S16'), d('S16'), d('Miss')],
              rules: sout)
              .outcome,
          VisitOutcome.normal);
    });
    test('Bust: Rest 0 mit Nicht-Doppel', () {
      final ev = evaluateDarts(remaining: 40, opened: true, darts: [d('S20'), d('S20')], rules: dout);
      expect(ev.isBust, isTrue);
      // Single Out darf das
      expect(
          evaluateDarts(remaining: 40, opened: true, darts: [d('S20'), d('S20')], rules: sout)
              .isCheckout,
          isTrue);
    });
    test('Checkout mit Doppel inkl. Bullseye', () {
      final a = evaluateDarts(remaining: 40, opened: true, darts: [d('D20')], rules: dout);
      expect(a.isCheckout, isTrue);
      expect(a.dartsCounted, 1);
      final b = evaluateDarts(remaining: 50, opened: true, darts: [d('Bull')], rules: dout);
      expect(b.isCheckout, isTrue);
      final c = evaluateDarts(remaining: 50, opened: true, darts: [d('S10'), d('D20')], rules: dout);
      expect(c.isCheckout, isTrue);
      expect(c.dartsCounted, 2);
    });
    test('Master Out: Triple beendet, Single nicht', () {
      expect(evaluateDarts(remaining: 60, opened: true, darts: [d('T20')], rules: mout).isCheckout,
          isTrue);
      expect(evaluateDarts(remaining: 20, opened: true, darts: [d('S20')], rules: mout).isBust,
          isTrue);
    });
    test('Darts nach Checkout/Bust sind ungültig, unvollständig auch', () {
      expect(
          () => evaluateDarts(
              remaining: 40, opened: true, darts: [d('D20'), d('S1')], rules: dout),
          throwsArgumentError);
      expect(() => evaluateDarts(remaining: 501, opened: true, darts: [d('T20')], rules: dout),
          throwsArgumentError);
      expect(
          () => evaluateDarts(
              remaining: 501, opened: true, darts: List.filled(4, d('S1')), rules: dout),
          throwsArgumentError);
    });
    test('Double In: nur Doppel eröffnet', () {
      const din = X01Rules(inMode: InMode.double);
      final ev = evaluateDarts(
          remaining: 501, opened: false, darts: [d('T20'), d('D10'), d('S5')], rules: din);
      expect(ev.points, 25); // T20 zählt nicht, D10 (20) + S5
      expect(ev.scoreAfter, 476);
      expect(ev.openedAfter, isTrue);
      final none = evaluateDarts(
          remaining: 501, opened: false, darts: [d('T20'), d('S19'), d('S5')], rules: din);
      expect(none.points, 0);
      expect(none.openedAfter, isFalse);
    });
  });

  group('Modus B (Gesamtpunkte)', () {
    test('Beispiele 180, 140, 100, 85, 60, 26, 0', () {
      var rest = 1001;
      for (final t in [180, 140, 100, 85, 60, 26, 0]) {
        final ev = evaluateTotal(remaining: rest, opened: true, total: t, rules: dout);
        expect(ev.outcome, VisitOutcome.normal);
        rest -= t;
      }
      expect(rest, 1001 - 591);
    });
    test('Bust über Rest und Rest 1', () {
      expect(evaluateTotal(remaining: 40, opened: true, total: 45, rules: dout).isBust, isTrue);
      expect(evaluateTotal(remaining: 41, opened: true, total: 40, rules: dout).isBust, isTrue);
      expect(evaluateTotal(remaining: 41, opened: true, total: 40, rules: sout).outcome,
          VisitOutcome.normal);
    });
    test('1 Restpunkt bei Double Out ist nicht beendbar', () {
      final ev = evaluateTotal(remaining: 2, opened: true, total: 1, rules: dout);
      expect(ev.isBust, isTrue);
    });
    test('Checkout verlangt mögliche Dartzahl', () {
      expect(evaluateTotal(remaining: 40, opened: true, total: 40, rules: dout, dartsUsed: 1).isCheckout,
          isTrue);
      expect(
          () => evaluateTotal(remaining: 100, opened: true, total: 100, rules: dout, dartsUsed: 1),
          throwsArgumentError);
      expect(evaluateTotal(remaining: 100, opened: true, total: 100, rules: dout, dartsUsed: 2).dartsCounted,
          2);
      // 3 Darts, aber Rest ist ungültiges Finish (169)
      expect(
          () => evaluateTotal(remaining: 169, opened: true, total: 169, rules: dout, dartsUsed: 3),
          throwsArgumentError);
    });
    test('unmögliche Summen werden abgelehnt', () {
      expect(() => evaluateTotal(remaining: 501, opened: true, total: 179, rules: dout),
          throwsArgumentError);
      expect(() => evaluateTotal(remaining: 501, opened: true, total: 181, rules: dout),
          throwsArgumentError);
      expect(() => evaluateTotal(remaining: 501, opened: true, total: -1, rules: dout),
          throwsArgumentError);
    });
    test('explizites Bust', () {
      final ev = evaluateTotal(remaining: 40, opened: true, total: 40, rules: dout, forceBust: true);
      expect(ev.isBust, isTrue);
      expect(ev.scoreAfter, 40);
    });
  });

  test('Checkout-Versuche aus Einzeldarts', () {
    // Rest 40: D20 daneben (S20), dann Rest 20 -> D10 verfehlt, D10 trifft
    expect(
        countCheckoutAttempts(
            startScore: 40,
            darts: [d('S20'), d('Miss'), d('D10')],
            rules: dout,
            opened: true),
        3);
    // Rest 100: kein Versuch beim ersten Dart, zweiter Dart bei Rest 40
    expect(
        countCheckoutAttempts(
            startScore: 100, darts: [d('T20'), d('D20')], rules: dout, opened: true),
        1);
    // 501: keine Versuche
    expect(
        countCheckoutAttempts(
            startScore: 501, darts: [d('T20'), d('T20'), d('T20')], rules: dout, opened: true),
        0);
  });
}
