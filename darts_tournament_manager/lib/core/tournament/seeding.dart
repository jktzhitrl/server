import 'dart:math';

import 'participant.dart';

/// Kleinste Zweierpotenz >= [n].
int nextPowerOfTwo(int n) {
  var p = 1;
  while (p < n) {
    p <<= 1;
  }
  return p;
}

/// Klassische Setzreihenfolge für einen K.-o.-Baum der Größe [size] (Zweierpotenz).
/// Gibt für jede Position (0-basiert, Paare 2i/2i+1) den Setzplatz (1-basiert) zurück:
/// z. B. size 8 -> [1,8,4,5,2,7,3,6]. Setzplatz 1 und 2 treffen sich erst im Finale.
List<int> seedOrder(int size) {
  if (size < 1 || (size & (size - 1)) != 0) {
    throw ArgumentError.value(size, 'size', 'muss Zweierpotenz sein');
  }
  var order = [1];
  while (order.length < size) {
    final next = order.length * 2;
    order = [
      for (final s in order) ...[s, next + 1 - s]
    ];
  }
  return order;
}

/// Ordnet die Teilnehmer nach Setzplatz; Ungesetzte werden zufällig angehängt.
List<Participant> rankParticipants(List<Participant> participants, Random rng) {
  final seeded = participants.where((p) => p.seed != null).toList()
    ..sort((a, b) => a.seed!.compareTo(b.seed!));
  final unseeded = participants.where((p) => p.seed == null).toList()..shuffle(rng);
  return [...seeded, ...unseeded];
}

/// Erzeugt die Positionsliste für einen K.-o.-Baum: Länge = nächste Zweierpotenz,
/// `null` = Freilos. Freilose gehen an die höchsten Setzplätze.
/// [useSeeds] = false: komplett zufällig (Gesetzte werden ignoriert).
List<Participant?> bracketPositions(
  List<Participant> participants, {
  bool useSeeds = true,
  Random? rng,
}) {
  if (participants.length < 2) {
    throw ArgumentError('Mindestens 2 Teilnehmer nötig');
  }
  final r = rng ?? Random();
  final ranked = useSeeds
      ? rankParticipants(participants, r)
      : (List<Participant>.from(participants)..shuffle(r));
  final size = nextPowerOfTwo(ranked.length);
  final order = seedOrder(size);
  return [
    for (final s in order) s <= ranked.length ? ranked[s - 1] : null,
  ];
}
