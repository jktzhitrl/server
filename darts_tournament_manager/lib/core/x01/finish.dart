import '../models/dart_throw.dart';
import '../models/rules.dart';

/// Regeln rund um Ein- und Auswurf. Reine Funktionen, vollständig testbar.

/// Ist [d] ein gültiger Dart, um ein Leg zu beenden?
bool isValidFinishDart(DartThrow d, OutMode out) {
  if (d.isMiss) return false;
  switch (out) {
    case OutMode.single:
      return true;
    case OutMode.double:
      return d.isDouble;
    case OutMode.master:
      return d.isDouble || d.isTriple;
  }
}

/// Zählt der Dart [d] zum Einwurf (bei Double-/Master-In)?
bool opensLeg(DartThrow d, InMode inMode) {
  if (d.isMiss) return false;
  switch (inMode) {
    case InMode.straight:
      return true;
    case InMode.double:
      return d.isDouble;
    case InMode.master:
      return d.isDouble || d.isTriple;
  }
}

/// Kleinster Restscore, der nach einem NICHT beendenden Dart erlaubt ist.
/// Single Out: 1, Double/Master Out: 2 (Rest 1 ist nicht beendbar -> Bust).
int minimumRemaining(OutMode out) => out == OutMode.single ? 1 : 2;

/// Kann der Restscore [score] mit EINEM Dart beendet werden?
bool isOneDartFinish(int score, OutMode out) {
  for (final d in DartThrow.allScoring) {
    if (d.score == score && isValidFinishDart(d, out)) return true;
  }
  return false;
}

/// Das Zielfeld bei einem Ein-Dart-Finish (z. B. 32 -> D16, 50 -> Bull).
/// Gibt bei mehreren Möglichkeiten (Single/Master Out) das "natürlichste"
/// Feld zurück (Double vor Triple vor Single). `null`, wenn kein Finish möglich.
DartThrow? finishTargetFor(int score, OutMode out) {
  DartThrow? best;
  var bestRank = 99;
  for (final d in DartThrow.allScoring) {
    if (d.score != score || !isValidFinishDart(d, out)) continue;
    final rank = d.isDouble ? 0 : (d.isTriple ? 1 : 2);
    if (rank < bestRank) {
      best = d;
      bestRank = rank;
    }
  }
  return best;
}

final Map<int, bool> _finishCache = {};

/// Gibt es eine Folge von GENAU [darts] Darts (1..3), deren Summe [score]
/// ergibt, bei der der letzte Dart ein gültiges Finish ist und kein früherer
/// Dart das Leg beendet oder einen Bust auslöst?
bool canFinishWithDarts(int score, int darts, OutMode out) {
  if (darts < 1 || darts > 3 || score < 1) return false;
  final key = (score * 4 + darts) * 4 + out.index;
  return _finishCache.putIfAbsent(key, () => _canFinish(score, darts, out));
}

bool _canFinish(int score, int darts, OutMode out) {
  if (darts == 1) return isOneDartFinish(score, out);
  final min = minimumRemaining(out);
  // Erster Dart: beliebiger Treffer oder Miss, danach muss der Rest >= min bleiben.
  if (score - 0 >= min && canFinishWithDarts(score, darts - 1, out)) return true;
  for (final d in DartThrow.allScoring) {
    final rest = score - d.score;
    if (rest >= min && canFinishWithDarts(rest, darts - 1, out)) return true;
  }
  return false;
}

/// Kann der Restscore [score] mit höchstens [maxDarts] Darts beendet werden?
bool canFinishWithin(int score, int maxDarts, OutMode out) {
  for (var n = 1; n <= maxDarts; n++) {
    if (canFinishWithDarts(score, n, out)) return true;
  }
  return false;
}

/// Höchster beendbarer Restscore (Double Out: 170, Master Out: 180, Single Out: 180).
int maxCheckout(OutMode out) => out == OutMode.double ? 170 : 180;

final Map<int, bool> _reachCache = {};

/// Ist die Punktsumme [total] mit genau [darts] Darts erreichbar
/// (Misses erlaubt)? Z. B. 179 ist mit 3 Darts nicht erreichbar.
bool isReachableTotal(int total, int darts) {
  if (total < 0 || darts < 1 || darts > 3) return false;
  final key = total * 4 + darts;
  return _reachCache.putIfAbsent(key, () {
    if (darts == 1) return total == 0 || DartThrow.allScoring.any((d) => d.score == total);
    if (isReachableTotal(total, darts - 1)) return true; // erster Dart Miss
    for (final d in DartThrow.allScoring) {
      if (total - d.score >= 0 && isReachableTotal(total - d.score, darts - 1)) return true;
    }
    return false;
  });
}
