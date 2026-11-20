import '../models/dart_throw.dart';
import '../models/ids.dart';
import '../models/rules.dart';
import 'finish.dart';
import 'visit.dart';

/// Ergebnis eines abgeschlossenen Legs.
class LegResult {
  final int legNo;
  final int setNo;
  final int winnerIndex;
  final int starterIndex;
  const LegResult(this.legNo, this.setNo, this.winnerIndex, this.starterIndex);
}

/// Wird geworfen, wenn eine Eingabe nicht zum aktuellen Spielstand passt
/// (z. B. zwei Schreiber gleichzeitig, oder Match schon beendet).
class MatchStateError extends StateError {
  MatchStateError(super.message);
}

/// Aus dem Visit-Log berechneter Spielstand (immer per Replay - keine
/// separate, auseinanderlaufende Wahrheit).
class X01State {
  final int legNo;
  final int setNo;
  final List<int> remaining;
  final List<bool> opened;
  final List<int> legsWon; // im laufenden Satz
  final List<int> setsWon;
  final List<int> totalLegsWon; // gesamtes Match (für Statistiken/Tabellen)
  final int currentPlayer;
  final int legStarter;
  final int? winnerIndex;
  final List<LegResult> legResults;
  final List<int> visitsInLeg;

  const X01State({
    required this.legNo,
    required this.setNo,
    required this.remaining,
    required this.opened,
    required this.legsWon,
    required this.setsWon,
    required this.totalLegsWon,
    required this.currentPlayer,
    required this.legStarter,
    required this.winnerIndex,
    required this.legResults,
    required this.visitsInLeg,
  });

  bool get isFinished => winnerIndex != null;
}

/// Unveränderliches X01-Match (301/501/701/1001, 1-n Spieler) mit
/// Event-Sourcing: alle Aufnahmen liegen in [visits]; Undo = letzte entfernen.
class X01Match {
  final X01Rules rules;
  final List<String> playerIds;
  final int firstStarter;

  /// Manuell festgelegter Anwurf für bestimmte Legs (z. B. Bull-Off im Decider).
  final Map<int, int> starterOverrides;
  final List<Visit> visits;
  late final X01State state = _replay();

  X01Match({
    required this.rules,
    required this.playerIds,
    this.firstStarter = 0,
    Map<int, int> starterOverrides = const {},
    List<Visit> visits = const [],
  })  : starterOverrides = Map.unmodifiable(starterOverrides),
        visits = List.unmodifiable(visits) {
    if (playerIds.isEmpty) throw ArgumentError('Mindestens ein Spieler nötig');
    if (firstStarter < 0 || firstStarter >= playerIds.length) {
      throw ArgumentError.value(firstStarter, 'firstStarter');
    }
  }

  int get playerCount => playerIds.length;

  /// Versionsnummer für optimistische Nebenläufigkeitskontrolle.
  int get version => visits.length;

  bool get isFinished => state.isFinished;

  int starterForLeg(int legNo) {
    final o = starterOverrides[legNo];
    if (o != null) return o;
    if (rules.starterRule == StarterRule.fixed) return firstStarter;
    return (firstStarter + legNo - 1) % playerCount;
  }

  X01State _replay() {
    final n = playerCount;
    var legNo = 1;
    var setNo = 1;
    var remaining = List<int>.filled(n, rules.startScore);
    var opened = List<bool>.filled(n, rules.inMode == InMode.straight);
    var legsWon = List<int>.filled(n, 0);
    final setsWon = List<int>.filled(n, 0);
    final totalLegs = List<int>.filled(n, 0);
    var visitsInLeg = List<int>.filled(n, 0);
    var starter = starterForLeg(1);
    var current = starter;
    int? winner;
    final results = <LegResult>[];

    for (final v in visits) {
      if (winner != null) {
        throw MatchStateError('Aufnahme nach Matchende im Log');
      }
      if (v.playerIndex != current || v.legNo != legNo || v.startScore != remaining[current]) {
        throw MatchStateError(
            'Inkonsistentes Visit-Log bei ${v.id} (erwartet Spieler $current, Leg $legNo, Rest ${remaining[current]})');
      }
      visitsInLeg[current]++;
      if (v.checkout) {
        results.add(LegResult(legNo, setNo, current, starter));
        totalLegs[current]++;
        legsWon[current]++;
        if (legsWon[current] >= rules.format.legsToWinSet) {
          setsWon[current]++;
          legsWon = List<int>.filled(n, 0);
          setNo++;
          if (setsWon[current] >= rules.format.setsToWin) {
            winner = current;
            remaining = List<int>.from(remaining)..[current] = 0;
            break;
          }
        }
        legNo++;
        remaining = List<int>.filled(n, rules.startScore);
        opened = List<bool>.filled(n, rules.inMode == InMode.straight);
        visitsInLeg = List<int>.filled(n, 0);
        starter = starterForLeg(legNo);
        current = starter;
      } else {
        remaining = List<int>.from(remaining)..[current] = v.scoreAfter;
        if (!v.bust && rules.inMode != InMode.straight && v.points > 0) {
          opened = List<bool>.from(opened)..[current] = true;
        }
        current = (current + 1) % n;
      }
    }
    return X01State(
      legNo: legNo,
      setNo: winner != null ? setNo - 1 : setNo,
      remaining: remaining,
      opened: opened,
      legsWon: legsWon,
      setsWon: setsWon,
      totalLegsWon: totalLegs,
      currentPlayer: current,
      legStarter: starter,
      winnerIndex: winner,
      legResults: results,
      visitsInLeg: visitsInLeg,
    );
  }

  /// Ist das nächste Leg ein Entscheidungsleg (alle Spieler eine Gewinnschwelle
  /// vom Matchsieg entfernt)? Nur sinnvoll bei 2 Spielern.
  bool get isDeciderLeg {
    if (playerCount != 2 || isFinished) return false;
    final f = rules.format;
    final s = state;
    final legsAtMatchPoint = s.legsWon.every((l) => l == f.legsToWinSet - 1);
    final setsAtMatchPoint = s.setsWon.every((x) => x == f.setsToWin - 1);
    return legsAtMatchPoint && setsAtMatchPoint && s.visitsInLeg.every((v) => v == 0);
  }

  /// Gibt eine Kopie mit festgelegtem Anwurf für [legNo] zurück (Bull-Off).
  /// Nur erlaubt, solange das Leg noch nicht begonnen hat.
  X01Match withStarterOverride(int legNo, int playerIndex) {
    if (playerIndex < 0 || playerIndex >= playerCount) {
      throw ArgumentError.value(playerIndex, 'playerIndex');
    }
    if (legNo != state.legNo || state.visitsInLeg.any((v) => v > 0)) {
      throw MatchStateError('Anwurf kann nur vor dem ersten Wurf des Legs gesetzt werden');
    }
    return X01Match(
      rules: rules,
      playerIds: playerIds,
      firstStarter: firstStarter,
      starterOverrides: {...starterOverrides, legNo: playerIndex},
      visits: visits,
    );
  }

  void _guard(int? expectedVersion) {
    if (isFinished) throw MatchStateError('Das Match ist bereits beendet');
    if (expectedVersion != null && expectedVersion != version) {
      throw MatchStateError(
          'Versionskonflikt: erwartet $expectedVersion, aktuell $version (gleichzeitige Eingabe)');
    }
  }

  X01Match _append(Visit v) => X01Match(
        rules: rules,
        playerIds: playerIds,
        firstStarter: firstStarter,
        starterOverrides: starterOverrides,
        visits: [...visits, v],
      );

  /// Modus A: Aufnahme aus Einzeldarts. Die Spielerreihenfolge, Busts,
  /// ungültige Finishes und Checkout werden automatisch erkannt.
  X01Match submitDarts(List<DartThrow> darts, {int? expectedVersion, DateTime? now}) {
    _guard(expectedVersion);
    final s = state;
    final p = s.currentPlayer;
    final ev = evaluateDarts(
      remaining: s.remaining[p],
      opened: s.opened[p],
      darts: darts,
      rules: rules,
    );
    final attempts = countCheckoutAttempts(
      startScore: s.remaining[p],
      darts: darts,
      rules: rules,
      opened: s.opened[p],
    );
    return _append(_toVisit(ev, p, darts, InputMode.perDart, attempts, now));
  }

  /// Modus B: Aufnahme aus Gesamtpunktzahl. [dartsUsed] ist beim Checkout
  /// erforderlich (1..3). [checkoutAttempts] = Darts auf ein beendbares Feld,
  /// falls bekannt (sonst `null` = unbekannt, nichts wird erfunden).
  X01Match submitTotal(
    int total, {
    int? dartsUsed,
    int? checkoutAttempts,
    bool bust = false,
    int? expectedVersion,
    DateTime? now,
  }) {
    _guard(expectedVersion);
    final s = state;
    final p = s.currentPlayer;
    final ev = evaluateTotal(
      remaining: s.remaining[p],
      opened: s.opened[p],
      total: total,
      rules: rules,
      dartsUsed: dartsUsed,
      forceBust: bust,
    );
    int? attempts = checkoutAttempts;
    if (attempts != null && (attempts < 0 || attempts > 3)) {
      throw ArgumentError.value(attempts, 'checkoutAttempts', 'muss 0..3 sein');
    }
    if (ev.isCheckout) {
      // Ein erfolgreicher Checkout ist immer mindestens ein Versuch.
      if (attempts != null && attempts < 1) attempts = 1;
    }
    return _append(_toVisit(ev, p, null, InputMode.total, attempts, now));
  }

  Visit _toVisit(VisitEvaluation ev, int p, List<DartThrow>? darts, InputMode mode,
      int? attempts, DateTime? now) {
    final s = state;
    return Visit(
      id: newId('v'),
      playerIndex: p,
      legNo: s.legNo,
      visitNo: s.visitsInLeg[p] + 1,
      startScore: ev.scoreBefore,
      scoreAfter: ev.scoreAfter,
      enteredTotal: ev.enteredTotal,
      points: ev.points,
      bust: ev.isBust,
      checkout: ev.isCheckout,
      darts: darts == null ? null : List.unmodifiable(darts),
      dartsThrown: ev.dartsCounted,
      checkoutAttempts: attempts,
      mode: mode,
      timestamp: now ?? DateTime.now().toUtc(),
    );
  }

  /// Vorschau einer noch laufenden Aufnahme (Modus A, Dart für Dart):
  /// verbleibender Rest, ob die Aufnahme damit abgeschlossen ist (3 Darts,
  /// Bust oder Checkout) und das Ergebnis.
  DraftPreview previewDraft(List<DartThrow> draft) {
    final s = state;
    final p = s.currentPlayer;
    if (draft.isEmpty) {
      return DraftPreview(
          remaining: s.remaining[p], complete: false, dartsLeft: 3, evaluation: null);
    }
    final ev = evaluateDarts(
      remaining: s.remaining[p],
      opened: s.opened[p],
      darts: draft,
      rules: rules,
      allowIncomplete: true,
    );
    final complete = ev.outcome != VisitOutcome.normal || draft.length == 3;
    return DraftPreview(
      remaining: ev.scoreAfter,
      complete: complete,
      dartsLeft: complete ? 0 : 3 - draft.length,
      evaluation: ev,
    );
  }

  /// Rückgängig: entfernt die letzte Aufnahme.
  X01Match undo() {
    if (visits.isEmpty) throw MatchStateError('Nichts rückgängig zu machen');
    return X01Match(
      rules: rules,
      playerIds: playerIds,
      firstStarter: firstStarter,
      starterOverrides: starterOverrides,
      visits: visits.sublist(0, visits.length - 1),
    );
  }

  /// Letzte Aufnahme ersetzen: entfernt sie und trägt per [builder] eine neue
  /// ein. Schlägt die neue Eingabe fehl, bleibt das Original unverändert.
  X01Match replaceLast(X01Match Function(X01Match base) builder) {
    final base = undo();
    return builder(base);
  }

  /// Letzte Aufnahme oder `null`.
  Visit? get lastVisit => visits.isEmpty ? null : visits.last;

  /// 3-Dart-Average eines Spielers im laufenden Leg.
  double? legAverage(int playerIndex) {
    final s = state;
    final mine = visits.where((v) => v.legNo == s.legNo && v.playerIndex == playerIndex);
    final darts = mine.fold<int>(0, (a, v) => a + v.dartsThrown);
    if (darts == 0) return null;
    return mine.fold<int>(0, (a, v) => a + v.points) / darts * 3;
  }

  Map<String, dynamic> toJson() => {
        'rules': rules.toJson(),
        'playerIds': playerIds,
        'firstStarter': firstStarter,
        'starterOverrides': starterOverrides.map((k, v) => MapEntry('$k', v)),
        'visits': visits.map((v) => v.toJson()).toList(),
      };

  factory X01Match.fromJson(Map<String, dynamic> j) => X01Match(
        rules: X01Rules.fromJson(Map<String, dynamic>.from(j['rules'] as Map)),
        playerIds: List<String>.from(j['playerIds'] as List),
        firstStarter: (j['firstStarter'] as num?)?.toInt() ?? 0,
        starterOverrides: (j['starterOverrides'] as Map? ?? {})
            .map((k, v) => MapEntry(int.parse('$k'), (v as num).toInt())),
        visits: (j['visits'] as List? ?? [])
            .map((e) => Visit.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  /// Der Dart, der zum Beenden nötig wäre (für Anzeige), falls ein Ein-Dart-Finish möglich.
  DartThrow? get currentFinishTarget =>
      finishTargetFor(state.remaining[state.currentPlayer], rules.outMode);
}


/// Zwischenstand einer laufenden Aufnahme.
class DraftPreview {
  final int remaining;
  final bool complete;
  final int dartsLeft;
  final VisitEvaluation? evaluation;
  const DraftPreview({
    required this.remaining,
    required this.complete,
    required this.dartsLeft,
    required this.evaluation,
  });
}
