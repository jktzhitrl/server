// ignore_for_file: avoid_print
// Erzeugt Testvektoren aus der Dart-Spiellogik, gegen die der TypeScript-Port in
// functions/ geprüft wird (Paritätstest). Ausführen:
//   dart run tool/gen_vectors.dart > functions/test/vectors.json
import 'dart:convert';
import 'dart:math';

import 'package:darts_tournament_manager/core/checkout/checkout_calculator.dart';
import 'package:darts_tournament_manager/core/models/dart_throw.dart';
import 'package:darts_tournament_manager/core/models/rules.dart';
import 'package:darts_tournament_manager/core/x01/finish.dart';
import 'package:darts_tournament_manager/core/x01/visit.dart';

Map<String, dynamic> outcome(VisitEvaluation e) => {
      'outcome': e.outcome.name,
      'scoreAfter': e.scoreAfter,
      'points': e.points,
      'enteredTotal': e.enteredTotal,
      'dartsCounted': e.dartsCounted,
      'openedAfter': e.openedAfter,
    };

void main() {
  final rng = Random(2024);
  final remainings = [501, 301, 170, 167, 141, 121, 100, 99, 81, 64, 60, 50, 41, 40, 33, 32, 24, 20, 3, 2, 1, 180, 100, 57];
  final darts = [...DartThrow.allScoring, DartThrow.miss];

  final dartCases = <Map<String, dynamic>>[];
  for (final out in OutMode.values) {
    for (final inMode in InMode.values) {
      for (var i = 0; i < 260; i++) {
        final rem = remainings[rng.nextInt(remainings.length)];
        final len = rng.nextInt(5) == 0 ? 1 + rng.nextInt(3) : 3;
        final ds = [for (var k = 0; k < len; k++) darts[rng.nextInt(darts.length)]];
        // Bevorzuge spannende Fälle: oft Checkout-nahe Darts
        final opened = inMode == InMode.straight || rng.nextBool();
        final rules = X01Rules(outMode: out, inMode: inMode);
        Map<String, dynamic> expected;
        try {
          expected = outcome(evaluateDarts(remaining: rem, opened: opened, darts: ds, rules: rules));
        } on ArgumentError {
          expected = {'error': true};
        }
        dartCases.add({
          'remaining': rem,
          'opened': opened,
          'darts': ds.map((d) => d.toJson()).toList(),
          'outMode': out.name,
          'inMode': inMode.name,
          'expected': expected,
        });
      }
    }
  }

  // Konstruierte Checkout-nahe Fälle: gültige Wege, Varianten mit falschem
  // Abschluss-Dart und Aufnahmen mit Rest 1.
  for (final out in OutMode.values) {
    final calc = CheckoutCalculator(outMode: out);
    for (var i = 0; i < 300; i++) {
      final rem = 2 + rng.nextInt(169);
      final routes = calc.allRoutes(rem);
      var ds = routes.isEmpty
          ? [for (var k = 0; k < 3; k++) darts[rng.nextInt(darts.length)]]
          : [...routes[rng.nextInt(routes.length)].darts];
      if (routes.isNotEmpty && rng.nextBool()) {
        final last = ds.last;
        // Abschluss-Dart durch Single gleicher Zahl ersetzen (ungültiges Finish)
        if (!last.isBull) ds = [...ds.take(ds.length - 1), DartThrow.single(last.number)];
      }
      if (ds.length > 3) ds = ds.take(3).toList();
      final rules = X01Rules(outMode: out);
      Map<String, dynamic> expected;
      try {
        expected = outcome(evaluateDarts(remaining: rem, opened: true, darts: ds, rules: rules));
      } on ArgumentError {
        expected = {'error': true};
      }
      dartCases.add({
        'remaining': rem,
        'opened': true,
        'darts': ds.map((d) => d.toJson()).toList(),
        'outMode': out.name,
        'inMode': 'straight',
        'expected': expected,
      });
    }
  }

  final totalCases = <Map<String, dynamic>>[];
  for (final out in OutMode.values) {
    for (var i = 0; i < 500; i++) {
      final rem = remainings[rng.nextInt(remainings.length)];
      final total = rng.nextInt(10) == 0 ? rng.nextInt(190) - 5 : (rng.nextBool() ? rem : rng.nextInt(181));
      final used = rng.nextInt(4) == 0 ? null : 1 + rng.nextInt(3);
      final bust = rng.nextInt(12) == 0;
      Map<String, dynamic> expected;
      try {
        expected = outcome(evaluateTotal(
          remaining: rem,
          opened: true,
          total: total,
          rules: X01Rules(outMode: out),
          dartsUsed: used,
          forceBust: bust,
        ));
      } on ArgumentError {
        expected = {'error': true};
      }
      totalCases.add({
        'remaining': rem,
        'total': total,
        'dartsUsed': used,
        'bust': bust,
        'outMode': out.name,
        'expected': expected,
      });
    }
  }

  final finishTable = <String, dynamic>{};
  for (final out in OutMode.values) {
    finishTable[out.name] = [
      for (var s = 0; s <= 200; s++)
        [for (var n = 1; n <= 3; n++) canFinishWithDarts(s, n, out)],
    ];
  }
  final reachable = [
    for (var t = 0; t <= 200; t++) [for (var n = 1; n <= 3; n++) isReachableTotal(t, n)],
  ];

  print(jsonEncode({
    'dartCases': dartCases,
    'totalCases': totalCases,
    'finishTable': finishTable,
    'reachable': reachable,
  }));
}
