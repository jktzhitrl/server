import '../models/dart_throw.dart';
import '../models/rules.dart';
import 'finish.dart';

enum VisitOutcome { normal, bust, checkout }

/// Wie eine Aufnahme erfasst wurde.
enum InputMode {
  /// Modus A: jeder Dart einzeln.
  perDart,

  /// Modus B: nur Gesamtpunktzahl.
  total,
}

/// Ergebnis der Auswertung einer Aufnahme (noch nicht persistiert).
class VisitEvaluation {
  final VisitOutcome outcome;
  final int scoreBefore;
  final int scoreAfter;

  /// Tatsächlich gutgeschriebene Punkte (0 bei Bust).
  final int points;

  /// Vom Schreiber bzw. aus den Darts ermittelte Summe (auch bei Bust).
  final int enteredTotal;

  /// Für Statistiken gezählte Darts (Bust = 3, Checkout = tatsächlich benutzte).
  final int dartsCounted;

  /// Ob der Spieler nach der Aufnahme "eingeworfen" hat.
  final bool openedAfter;

  const VisitEvaluation({
    required this.outcome,
    required this.scoreBefore,
    required this.scoreAfter,
    required this.points,
    required this.enteredTotal,
    required this.dartsCounted,
    required this.openedAfter,
  });

  bool get isBust => outcome == VisitOutcome.bust;
  bool get isCheckout => outcome == VisitOutcome.checkout;
}

/// Wertet eine Aufnahme aus einzelnen Darts (Modus A) aus.
///
/// Die Aufnahme endet mit dem ersten Checkout- oder Bust-Dart; weitere Darts
/// danach sind ungültig. Ohne Ende müssen genau 3 Darts übergeben werden.
VisitEvaluation evaluateDarts({
  required int remaining,
  required bool opened,
  required List<DartThrow> darts,
  required X01Rules rules,
  bool allowIncomplete = false,
}) {
  if (darts.isEmpty) throw ArgumentError('Keine Darts übergeben');
  if (darts.length > 3) throw ArgumentError('Maximal 3 Darts pro Aufnahme');
  var cur = remaining;
  var open = opened || rules.inMode == InMode.straight;
  var sum = 0;
  final min = minimumRemaining(rules.outMode);

  VisitEvaluation bust(int used) => VisitEvaluation(
        outcome: VisitOutcome.bust,
        scoreBefore: remaining,
        scoreAfter: remaining,
        points: 0,
        enteredTotal: sum,
        dartsCounted: 3,
        openedAfter: opened,
      );

  for (var i = 0; i < darts.length; i++) {
    final d = darts[i];
    if (!open) {
      if (opensLeg(d, rules.inMode)) {
        open = true;
      } else {
        continue; // zählt noch nicht
      }
    }
    sum += d.score;
    final next = cur - d.score;
    final isLast = i == darts.length - 1;
    if (next == 0) {
      if (!isValidFinishDart(d, rules.outMode)) {
        _ensureEnd(isLast, 'Bust');
        return bust(i + 1);
      }
      _ensureEnd(isLast, 'Checkout');
      return VisitEvaluation(
        outcome: VisitOutcome.checkout,
        scoreBefore: remaining,
        scoreAfter: 0,
        points: remaining,
        enteredTotal: sum,
        dartsCounted: i + 1,
        openedAfter: true,
      );
    }
    if (next < min) {
      _ensureEnd(isLast, 'Bust');
      return bust(i + 1);
    }
    cur = next;
  }
  if (darts.length != 3 && !allowIncomplete) {
    throw ArgumentError('Aufnahme unvollständig: ${darts.length} von 3 Darts');
  }
  return VisitEvaluation(
    outcome: VisitOutcome.normal,
    scoreBefore: remaining,
    scoreAfter: cur,
    points: remaining - cur,
    enteredTotal: sum,
    dartsCounted: darts.length,
    openedAfter: open,
  );
}

void _ensureEnd(bool isLast, String what) {
  if (!isLast) {
    throw ArgumentError('Nach $what dürfen keine weiteren Darts folgen');
  }
}

/// Wertet eine Aufnahme aus der Gesamtpunktzahl (Modus B) aus.
///
/// * [total] > Rest oder Rest 1 bei Double/Master Out -> Bust.
/// * [total] == Rest -> Checkout; dann muss [dartsUsed] angegeben werden und
///   der Checkout mit genau dieser Dartzahl möglich sein.
/// * [forceBust] markiert die Aufnahme explizit als Bust (z. B. letzter Dart
///   kein Doppel, obwohl die Summe passt).
VisitEvaluation evaluateTotal({
  required int remaining,
  required bool opened,
  required int total,
  required X01Rules rules,
  int? dartsUsed,
  bool forceBust = false,
}) {
  if (total < 0 || total > 180) {
    throw ArgumentError.value(total, 'total', 'muss 0..180 sein');
  }
  final used = dartsUsed ?? 3;
  if (used < 1 || used > 3) {
    throw ArgumentError.value(dartsUsed, 'dartsUsed', 'muss 1..3 sein');
  }
  VisitEvaluation bust() => VisitEvaluation(
        outcome: VisitOutcome.bust,
        scoreBefore: remaining,
        scoreAfter: remaining,
        points: 0,
        enteredTotal: total,
        dartsCounted: 3,
        openedAfter: opened,
      );

  if (forceBust) return bust();
  if (!isReachableTotal(total, 3)) {
    throw ArgumentError('$total ist mit 3 Darts nicht erreichbar');
  }
  if (!isReachableTotal(total, used)) {
    throw ArgumentError('$total ist mit $used Dart(s) nicht erreichbar');
  }
  final next = remaining - total;
  if (next < 0) return bust();
  if (next == 0) {
    if (!canFinishWithDarts(remaining, used, rules.outMode)) {
      throw ArgumentError(
          'Checkout von $remaining mit $used Dart(s) ist bei ${rules.label} nicht möglich');
    }
    return VisitEvaluation(
      outcome: VisitOutcome.checkout,
      scoreBefore: remaining,
      scoreAfter: 0,
      points: remaining,
      enteredTotal: total,
      dartsCounted: used,
      openedAfter: true,
    );
  }
  if (next < minimumRemaining(rules.outMode)) return bust();
  return VisitEvaluation(
    outcome: VisitOutcome.normal,
    scoreBefore: remaining,
    scoreAfter: next,
    points: total,
    enteredTotal: total,
    dartsCounted: 3,
    openedAfter: opened || total > 0 || rules.inMode == InMode.straight,
  );
}

/// Eine gespeicherte Aufnahme (Event im Event-Sourcing-Log eines Matches).
class Visit {
  final String id;
  final int playerIndex;

  /// Fortlaufende Leg-Nummer im Match (ab 1).
  final int legNo;

  /// Laufende Nummer der Aufnahme dieses Spielers im Leg (ab 1).
  final int visitNo;
  final int startScore;
  final int scoreAfter;
  final int enteredTotal;
  final int points;
  final bool bust;
  final bool checkout;

  /// Einzeldarts (nur Modus A). Bei Modus B bewusst `null` - es werden keine
  /// Einzeldaten erfunden.
  final List<DartThrow>? darts;

  /// Für Statistiken gezählte Darts.
  final int dartsThrown;

  /// Darts auf ein beendbares Feld ("Checkout-Versuche"); `null` = unbekannt.
  final int? checkoutAttempts;
  final InputMode mode;
  final DateTime timestamp;

  const Visit({
    required this.id,
    required this.playerIndex,
    required this.legNo,
    required this.visitNo,
    required this.startScore,
    required this.scoreAfter,
    required this.enteredTotal,
    required this.points,
    required this.bust,
    required this.checkout,
    required this.darts,
    required this.dartsThrown,
    required this.checkoutAttempts,
    required this.mode,
    required this.timestamp,
  });

  bool get hasDartData => darts != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'playerIndex': playerIndex,
        'legNo': legNo,
        'visitNo': visitNo,
        'startScore': startScore,
        'scoreAfter': scoreAfter,
        'enteredTotal': enteredTotal,
        'points': points,
        'bust': bust,
        'checkout': checkout,
        'darts': darts?.map((d) => d.toJson()).toList(),
        'dartsThrown': dartsThrown,
        'checkoutAttempts': checkoutAttempts,
        'mode': mode.name,
        'timestamp': timestamp.toUtc().toIso8601String(),
      };

  factory Visit.fromJson(Map<String, dynamic> j) => Visit(
        id: j['id'] as String,
        playerIndex: (j['playerIndex'] as num).toInt(),
        legNo: (j['legNo'] as num).toInt(),
        visitNo: (j['visitNo'] as num).toInt(),
        startScore: (j['startScore'] as num).toInt(),
        scoreAfter: (j['scoreAfter'] as num).toInt(),
        enteredTotal: (j['enteredTotal'] as num).toInt(),
        points: (j['points'] as num).toInt(),
        bust: j['bust'] as bool,
        checkout: j['checkout'] as bool,
        darts: (j['darts'] as List?)
            ?.map(DartThrow.fromJson)
            .toList(growable: false),
        dartsThrown: (j['dartsThrown'] as num).toInt(),
        checkoutAttempts: (j['checkoutAttempts'] as num?)?.toInt(),
        mode: InputMode.values.byName(j['mode'] as String),
        timestamp: DateTime.parse(j['timestamp'] as String),
      );
}

/// Zählt Checkout-Versuche aus Einzeldarts: jeder Dart, der geworfen wird,
/// während der aktuelle Rest mit einem Dart beendbar ist.
int countCheckoutAttempts({
  required int startScore,
  required List<DartThrow> darts,
  required X01Rules rules,
  required bool opened,
}) {
  var cur = startScore;
  var open = opened || rules.inMode == InMode.straight;
  var attempts = 0;
  for (final d in darts) {
    if (!open) {
      if (opensLeg(d, rules.inMode)) {
        open = true;
      } else {
        continue;
      }
    }
    if (isOneDartFinish(cur, rules.outMode)) attempts++;
    final next = cur - d.score;
    if (next <= 0 || next < minimumRemaining(rules.outMode)) break;
    cur = next;
  }
  return attempts;
}
