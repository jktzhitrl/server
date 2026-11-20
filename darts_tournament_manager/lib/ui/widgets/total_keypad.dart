import 'package:flutter/material.dart';

import '../../core/x01/finish.dart';
import '../../core/models/rules.dart';

/// Ergebnis der Schnelleingabe.
class TotalEntry {
  final int total;
  final int? dartsUsed;
  final int? checkoutAttempts;
  final bool bust;
  const TotalEntry(this.total, {this.dartsUsed, this.checkoutAttempts, this.bust = false});
}

/// Modus B: nur die Gesamtpunktzahl der Aufnahme eingeben.
class TotalKeypad extends StatefulWidget {
  /// Restpunkte des Spielers am Wurf.
  final int remaining;
  final OutMode outMode;
  final bool enabled;
  final Future<void> Function(TotalEntry entry) onSubmit;
  const TotalKeypad({
    super.key,
    required this.remaining,
    required this.outMode,
    required this.onSubmit,
    this.enabled = true,
  });

  @override
  State<TotalKeypad> createState() => _TotalKeypadState();
}

class _TotalKeypadState extends State<TotalKeypad> {
  String _text = '';
  int? _checkoutAttempts; // null = unbekannt
  bool _busy = false;

  int get _value => _text.isEmpty ? 0 : int.parse(_text);

  void _digit(String d) {
    final next = _text + d;
    if (next.length > 3 || int.parse(next) > 180) return;
    setState(() => _text = int.parse(next).toString());
  }

  Future<void> _submit(int total, {bool bust = false}) async {
    if (_busy) return;
    int? darts;
    final isCheckout = !bust && total == widget.remaining;
    if (isCheckout) {
      darts = await _askDarts();
      if (darts == null) return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(TotalEntry(total,
          dartsUsed: darts, checkoutAttempts: _checkoutAttempts, bust: bust));
      if (mounted) {
        setState(() {
          _text = '';
          _checkoutAttempts = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int?> _askDarts() {
    return showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Checkout ${widget.remaining}: Mit wie vielen Darts?',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(children: [
              for (var n = 1; n <= 3; n++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: FilledButton(
                      key: Key('checkout-darts-$n'),
                      onPressed: canFinishWithDarts(widget.remaining, n, widget.outMode)
                          ? () => Navigator.pop(ctx, n)
                          : null,
                      child: Text('$n Dart${n > 1 ? 's' : ''}'),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inRange = widget.remaining <= maxCheckout(widget.outMode) &&
        canFinishWithin(widget.remaining, 3, widget.outMode);
    final enabled = widget.enabled && !_busy;
    Widget key(String label, VoidCallback? onTap, {Key? k}) => Padding(
          padding: const EdgeInsets.all(3),
          child: FilledButton.tonal(
            key: k,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
            onPressed: enabled ? onTap : null,
            child: Text(label, style: const TextStyle(fontSize: 22)),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14)),
          child: Text(_text.isEmpty ? '0' : _text,
              key: const Key('totalDisplay'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final q in [180, 140, 100, 85, 60, 45, 41, 26, 0])
              ActionChip(
                key: Key('quick-$q'),
                label: Text('$q'),
                onPressed: enabled ? () => setState(() => _text = '$q') : null,
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final row in [
          ['7', '8', '9'],
          ['4', '5', '6'],
          ['1', '2', '3'],
        ])
          Row(children: [
            for (final d in row) Expanded(child: key(d, () => _digit(d), k: Key('key-$d'))),
          ]),
        Row(children: [
          Expanded(
              child: Padding(
            padding: const EdgeInsets.all(3),
            child: FilledButton.tonal(
              key: const Key('key-back'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: enabled
                  ? () => setState(() => _text = _text.isEmpty ? '' : _text.substring(0, _text.length - 1))
                  : null,
              child: const Icon(Icons.backspace_outlined),
            ),
          )),
          Expanded(child: key('0', () => _digit('0'), k: const Key('key-0'))),
          Expanded(
              child: Padding(
            padding: const EdgeInsets.all(3),
            child: FilledButton(
              key: const Key('key-ok'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: enabled ? () => _submit(_value) : null,
              child: const Icon(Icons.check, size: 28),
            ),
          )),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
              child: OutlinedButton(
            key: const Key('key-bust'),
            onPressed: enabled ? () => _submit(_value, bust: true) : null,
            child: const Text('Bust'),
          )),
        ]),
        if (inRange) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              const Text('Darts auf Doppel:'),
              for (final n in [0, 1, 2, 3])
                ChoiceChip(
                  key: Key('attempts-$n'),
                  label: Text('$n'),
                  selected: _checkoutAttempts == n,
                  onSelected: enabled
                      ? (s) => setState(() => _checkoutAttempts = s ? n : null)
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
