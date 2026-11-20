import '../models/dart_throw.dart';

/// Around the Clock: Reihenfolge 1..20, danach Bull. Es zählt jeder Treffer
/// (Single/Double/Triple) auf die gesuchte Zahl. Wer zuerst das Bull trifft,
/// gewinnt. Optional ([skipAhead]) springt ein Double um 2 und ein Triple um 3
/// Ziele weiter. Mit nur einem Spieler dient der Modus als Trainingsmodus.
class AroundTheClockMatch {
  /// Anzahl Ziele: 1..20 und Bull.
  static const int targetCount = 21;

  final List<String> playerIds;
  final bool skipAhead;
  final List<DartThrow> darts;
  late final ClockState state = _replay();

  AroundTheClockMatch({
    required this.playerIds,
    this.skipAhead = false,
    List<DartThrow> darts = const [],
  }) : darts = List.unmodifiable(darts) {
    if (playerIds.isEmpty) throw ArgumentError('Mindestens ein Spieler nötig');
  }

  int get version => darts.length;

  /// Anzeigename des Ziels mit Index [i] (0..20).
  static String targetLabel(int i) => i >= 20 ? 'Bull' : '${i + 1}';

  ClockState _replay() {
    final n = playerIds.length;
    final progress = List<int>.filled(n, 0); // Index des gesuchten Ziels
    final hits = List<int>.filled(n, 0);
    var current = 0;
    var dartsInVisit = 0;
    int? winner;
    for (final d in darts) {
      if (winner != null) throw StateError('Dart nach Spielende im Log');
      final p = progress[current];
      final target = p >= 20 ? 25 : p + 1;
      if (!d.isMiss && d.number == target) {
        final steps = skipAhead && p < 20 ? d.multiplier : 1;
        progress[current] = (p + steps).clamp(0, targetCount);
        hits[current]++;
        if (progress[current] >= targetCount) winner = current;
      }
      dartsInVisit++;
      if (winner == null && dartsInVisit == 3) {
        dartsInVisit = 0;
        if (n > 1) current = (current + 1) % n;
      }
    }
    return ClockState(
      progress: progress,
      hits: hits,
      currentPlayer: current,
      dartsInVisit: dartsInVisit,
      winnerIndex: winner,
    );
  }

  AroundTheClockMatch addDart(DartThrow d, {int? expectedVersion}) {
    if (state.winnerIndex != null) throw StateError('Das Spiel ist bereits beendet');
    if (expectedVersion != null && expectedVersion != version) {
      throw StateError('Versionskonflikt: erwartet $expectedVersion, aktuell $version');
    }
    return AroundTheClockMatch(
        playerIds: playerIds, skipAhead: skipAhead, darts: [...darts, d]);
  }

  AroundTheClockMatch undo() {
    if (darts.isEmpty) throw StateError('Nichts rückgängig zu machen');
    return AroundTheClockMatch(
        playerIds: playerIds,
        skipAhead: skipAhead,
        darts: darts.sublist(0, darts.length - 1));
  }
}

class ClockState {
  /// Index des aktuell gesuchten Ziels je Spieler (21 = fertig).
  final List<int> progress;
  final List<int> hits;
  final int currentPlayer;
  final int dartsInVisit;
  final int? winnerIndex;
  const ClockState({
    required this.progress,
    required this.hits,
    required this.currentPlayer,
    required this.dartsInVisit,
    required this.winnerIndex,
  });
}
