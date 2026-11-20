import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/dart_throw.dart';

/// Geometrie der Dartscheibe (Turnierscheibe, Maße in Bruchteilen des
/// Außenradius der Doppel). Rein rechnerisch, daher unabhängig vom UI testbar.
class DartboardGeometry {
  /// Zahlen im Uhrzeigersinn, 20 oben.
  static const List<int> order = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

  static const double bullseye = 6.35 / 170;
  static const double outerBull = 15.9 / 170;
  static const double tripleInner = 99 / 170;
  static const double tripleOuter = 107 / 170;
  static const double doubleInner = 162 / 170;
  static const double doubleOuter = 1.0;

  /// Ermittelt den getroffenen Dart für einen Punkt [p] in einem Feld der
  /// Größe [size]. Gibt `null` zurück, wenn der Punkt außerhalb der
  /// Scheibe liegt (kein Treffer).
  static DartThrow? hit(Offset p, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * boardScale;
    final d = p - center;
    final r = d.distance / radius;
    if (r > doubleOuter) return null;
    if (r <= bullseye) return DartThrow.bullseye;
    if (r <= outerBull) return DartThrow.outerBull;
    // Winkel im Uhrzeigersinn ab 12 Uhr, in Grad.
    var deg = math.atan2(d.dx, -d.dy) * 180 / math.pi;
    if (deg < 0) deg += 360;
    final index = ((deg + 9) / 18).floor() % 20;
    final number = order[index];
    if (r >= doubleInner) return DartThrow.double(number);
    if (r >= tripleInner && r <= tripleOuter) return DartThrow.triple(number);
    return DartThrow.single(number);
  }

  /// Anteil der Widgetgröße, den die Scheibe einnimmt (Rand für Ziffern).
  static const double boardScale = 0.86;
}

/// Interaktive Dartscheibe: Tippen auf ein Feld liefert den passenden [DartThrow].
class DartboardInput extends StatelessWidget {
  final void Function(DartThrow dart) onDart;
  final bool enabled;
  const DartboardInput({super.key, required this.onDart, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          key: const Key('dartboard'),
          behavior: HitTestBehavior.opaque,
          onTapUp: enabled
              ? (d) {
                  final hit = DartboardGeometry.hit(d.localPosition, size);
                  if (hit != null) onDart(hit);
                }
              : null,
          child: CustomPaint(painter: _BoardPainter(enabled), size: size),
        );
      }),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final bool enabled;
  _BoardPainter(this.enabled);

  static const _black = Color(0xFF15191A);
  static const _cream = Color(0xFFE9DFC1);
  static const _red = Color(0xFFC0392B);
  static const _green = Color(0xFF1E8449);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * DartboardGeometry.boardScale;
    final paint = Paint()..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 1.08, paint..color = const Color(0xFF050606));

    void ring(double inner, double outer, Color color, int i) {
      final start = (-90 + i * 18 - 9) * math.pi / 180;
      final path = Path()
        ..arcTo(Rect.fromCircle(center: center, radius: radius * outer), start, 18 * math.pi / 180, true)
        ..arcTo(Rect.fromCircle(center: center, radius: radius * inner), start + 18 * math.pi / 180,
            -18 * math.pi / 180, false)
        ..close();
      canvas.drawPath(path, paint..color = color);
    }

    for (var i = 0; i < 20; i++) {
      final dark = i.isEven;
      final single = dark ? _black : _cream;
      final multi = dark ? _red : _green;
      ring(DartboardGeometry.outerBull, DartboardGeometry.tripleInner, single, i);
      ring(DartboardGeometry.tripleInner, DartboardGeometry.tripleOuter, multi, i);
      ring(DartboardGeometry.tripleOuter, DartboardGeometry.doubleInner, single, i);
      ring(DartboardGeometry.doubleInner, DartboardGeometry.doubleOuter, multi, i);
    }
    canvas.drawCircle(center, radius * DartboardGeometry.outerBull, paint..color = _green);
    canvas.drawCircle(center, radius * DartboardGeometry.bullseye, paint..color = _red);

    // Drahtrahmen
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFFB0B7BA);
    for (final r in [
      DartboardGeometry.outerBull,
      DartboardGeometry.tripleInner,
      DartboardGeometry.tripleOuter,
      DartboardGeometry.doubleInner,
      DartboardGeometry.doubleOuter
    ]) {
      canvas.drawCircle(center, radius * r, wire);
    }
    for (var i = 0; i < 20; i++) {
      final a = (-90 + i * 18 - 9) * math.pi / 180;
      canvas.drawLine(center + Offset(math.cos(a), math.sin(a)) * radius * DartboardGeometry.outerBull,
          center + Offset(math.cos(a), math.sin(a)) * radius, wire);
    }

    // Ziffern
    for (var i = 0; i < 20; i++) {
      final a = (-90 + i * 18) * math.pi / 180;
      final pos = center + Offset(math.cos(a), math.sin(a)) * radius * 1.065;
      final tp = TextPainter(
        text: TextSpan(
            text: '${DartboardGeometry.order[i]}',
            style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontSize: radius * 0.1,
                fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => old.enabled != enabled;
}

/// Eingabe über Schaltflächen: Multiplikator wählen, dann Zahl.
class DartButtons extends StatefulWidget {
  final void Function(DartThrow dart) onDart;
  final bool enabled;
  const DartButtons({super.key, required this.onDart, this.enabled = true});

  @override
  State<DartButtons> createState() => _DartButtonsState();
}

class _DartButtonsState extends State<DartButtons> {
  int _mult = 1;

  void _tap(int n) {
    widget.onDart(DartThrow(_mult, n));
    if (_mult != 1) setState(() => _mult = 1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('Single')),
            ButtonSegment(value: 2, label: Text('Double')),
            ButtonSegment(value: 3, label: Text('Triple')),
          ],
          selected: {_mult},
          onSelectionChanged: widget.enabled ? (s) => setState(() => _mult = s.first) : null,
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.5,
          children: [
            for (var n = 1; n <= 20; n++)
              FilledButton.tonal(
                key: Key('dart-$n'),
                style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: _mult == 3
                        ? cs.errorContainer
                        : _mult == 2
                            ? cs.primaryContainer
                            : null),
                onPressed: widget.enabled ? () => _tap(n) : null,
                child: Text('$n'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  key: const Key('dart-25'),
                  onPressed: widget.enabled ? () => widget.onDart(DartThrow.outerBull) : null,
                  child: const Text('25'))),
          const SizedBox(width: 6),
          Expanded(
              child: OutlinedButton(
                  key: const Key('dart-bull'),
                  onPressed: widget.enabled ? () => widget.onDart(DartThrow.bullseye) : null,
                  child: const Text('Bull'))),
          const SizedBox(width: 6),
          Expanded(
              child: OutlinedButton(
                  key: const Key('dart-miss'),
                  onPressed: widget.enabled ? () => widget.onDart(DartThrow.miss) : null,
                  child: const Text('Miss'))),
        ]),
      ],
    );
  }
}
