import 'dart:math';

final Random _rng = Random();
int _counter = 0;

/// Erzeugt eine kollisionsarme ID ohne externe Abhängigkeit
/// (Zeitstempel + Zähler + Zufall). Reicht für Dokument-IDs, die zusätzlich
/// durch Firestore-Pfade und Security Rules abgesichert sind.
String newId([String prefix = '']) {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final c = (_counter++).toRadixString(36);
  final r = _rng.nextInt(1 << 20).toRadixString(36);
  return '$prefix$t$c$r';
}
