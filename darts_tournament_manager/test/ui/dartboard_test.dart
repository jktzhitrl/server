import 'dart:math' as math;

import 'package:darts_tournament_manager/core/models/dart_throw.dart';
import 'package:darts_tournament_manager/ui/widgets/dartboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(400, 400);
  const c = Offset(200, 200);
  // Radius der Scheibe in Pixeln
  const r = 200 * DartboardGeometry.boardScale;

  /// Punkt bei Winkel [deg] (im Uhrzeigersinn ab 12 Uhr) und Radius-Anteil [f].
  Offset at(double deg, double f) {
    final a = deg * math.pi / 180;
    return c + Offset(math.sin(a), -math.cos(a)) * r * f;
  }

  test('Bull und Outer Bull', () {
    expect(DartboardGeometry.hit(c, size), DartThrow.bullseye);
    expect(DartboardGeometry.hit(at(45, 0.07), size), DartThrow.outerBull);
  });

  test('Zahlenkranz: Ecken der Scheibe', () {
    final expected = {0.0: 20, 90.0: 6, 180.0: 3, 270.0: 11, 18.0: 1, 342.0: 5, 126.0: 10 + 0};
    expect(DartboardGeometry.hit(at(0, 0.8), size), DartThrow.single(20));
    expect(DartboardGeometry.hit(at(90, 0.8), size), DartThrow.single(6));
    expect(DartboardGeometry.hit(at(180, 0.8), size), DartThrow.single(3));
    expect(DartboardGeometry.hit(at(270, 0.8), size), DartThrow.single(11));
    expect(DartboardGeometry.hit(at(18, 0.8), size), DartThrow.single(1));
    expect(DartboardGeometry.hit(at(342, 0.8), size), DartThrow.single(5));
    expect(expected.isNotEmpty, isTrue);
  });

  test('alle 20 Segmente werden in der Mitte getroffen', () {
    for (var i = 0; i < 20; i++) {
      expect(DartboardGeometry.hit(at(i * 18.0, 0.8), size), DartThrow.single(DartboardGeometry.order[i]));
      expect(DartboardGeometry.hit(at(i * 18.0, 0.61), size), DartThrow.triple(DartboardGeometry.order[i]));
      expect(DartboardGeometry.hit(at(i * 18.0, 0.98), size), DartThrow.double(DartboardGeometry.order[i]));
      expect(DartboardGeometry.hit(at(i * 18.0, 0.35), size), DartThrow.single(DartboardGeometry.order[i]));
    }
  });

  test('Segmentgrenzen und außerhalb', () {
    // Knapp links/rechts von 12 Uhr bleibt 20
    expect(DartboardGeometry.hit(at(8, 0.8), size), DartThrow.single(20));
    expect(DartboardGeometry.hit(at(352, 0.8), size), DartThrow.single(20));
    expect(DartboardGeometry.hit(at(10, 0.8), size), DartThrow.single(1));
    // Außerhalb der Doppel
    expect(DartboardGeometry.hit(at(0, 1.05), size), isNull);
    expect(DartboardGeometry.hit(const Offset(0, 0), size), isNull);
  });

  test('Dartreihenfolge ist vollständig und eindeutig', () {
    expect(DartboardGeometry.order.toSet().length, 20);
    expect(DartboardGeometry.order.toSet(), {for (var i = 1; i <= 20; i++) i});
  });

  testWidgets('Tippen auf die Scheibe liefert den Dart', (tester) async {
    DartThrow? got;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 400, height: 400, child: DartboardInput(onDart: (d) => got = d))))));
    final box = tester.getRect(find.byKey(const Key('dartboard')));
    await tester.tapAt(box.center + const Offset(0, -150)); // oben, ~0.76 -> S20? (r=150/172)
    expect(got, isNotNull);
    expect(got!.number, 20);
  });
}
