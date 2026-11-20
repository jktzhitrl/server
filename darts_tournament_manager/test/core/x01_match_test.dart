import 'package:darts_tournament_manager/core/models/dart_throw.dart';
import 'package:darts_tournament_manager/core/models/rules.dart';
import 'package:darts_tournament_manager/core/x01/x01_match.dart';
import 'package:flutter_test/flutter_test.dart';

DartThrow d(String s) => DartThrow.parse(s);

X01Match newMatch({
  int start = 501,
  MatchFormat format = const MatchFormat(legsToWinSet: 2),
  OutMode out = OutMode.double,
  InMode inMode = InMode.straight,
  StarterRule starter = StarterRule.alternating,
  int players = 2,
}) =>
    X01Match(
      rules: X01Rules(
          startScore: start, format: format, outMode: out, inMode: inMode, starterRule: starter),
      playerIds: [for (var i = 0; i < players; i++) 'p$i'],
    );

void main() {
  draftTests();
  test('Spielerwechsel, Restscore und Aufnahmen', () {
    var m = newMatch();
    expect(m.state.currentPlayer, 0);
    m = m.submitTotal(100);
    expect(m.state.remaining, [401, 501]);
    expect(m.state.currentPlayer, 1);
    m = m.submitTotal(60);
    expect(m.state.remaining, [401, 441]);
    expect(m.state.currentPlayer, 0);
    expect(m.version, 2);
  });

  test('Modus A: Auto-Auswertung und Bust stellt Score wieder her', () {
    var m = newMatch(start: 301);
    m = m.submitDarts([d('T20'), d('T20'), d('T20')]); // 121 Rest
    m = m.submitTotal(0);
    expect(m.state.remaining[0], 121);
    m = m.submitDarts([d('T20'), d('T20')]); // 121-120 = 1 -> Bust
    expect(m.lastVisit!.bust, isTrue);
    expect(m.state.remaining[0], 121);
    expect(m.state.currentPlayer, 1);
  });

  test('Checkout beendet Leg; Anwurf wechselt; Legs/Sets laufen', () {
    var m = newMatch(start: 40, format: const MatchFormat(legsToWinSet: 2));
    // Spieler 0 beginnt Leg 1
    m = m.submitDarts([d('D20')]);
    expect(m.state.legResults.single.winnerIndex, 0);
    expect(m.state.totalLegsWon, [1, 0]);
    expect(m.state.legNo, 2);
    expect(m.state.currentPlayer, 1, reason: 'Anwurf wechselt');
    m = m.submitDarts([d('D20')]);
    expect(m.state.totalLegsWon, [1, 1]);
    expect(m.state.currentPlayer, 0);
    m = m.submitDarts([d('D20')]);
    expect(m.isFinished, isTrue);
    expect(m.state.winnerIndex, 0);
    expect(m.state.setsWon, [1, 0]);
    expect(() => m.submitTotal(10), throwsA(isA<MatchStateError>()));
  });

  test('fester Anwurf', () {
    var m = newMatch(start: 40, starter: StarterRule.fixed);
    m = m.submitDarts([d('D20')]);
    expect(m.state.currentPlayer, 0);
  });

  test('Sätze: First to 2 Sätze, je 2 Legs', () {
    var m = newMatch(
        start: 40, format: const MatchFormat(legsToWinSet: 2, setsToWin: 2));
    // Spieler 0 gewinnt jedes Leg, auch wenn Anwurf wechselt: Gegner wirft 0 (Miss)
    int guard = 0;
    while (!m.isFinished && guard++ < 50) {
      final p = m.state.currentPlayer;
      m = p == 0 ? m.submitDarts([d('D20')]) : m.submitTotal(0);
    }
    expect(m.isFinished, isTrue);
    expect(m.state.winnerIndex, 0);
    expect(m.state.setsWon[0], 2);
    expect(m.state.legResults.length, 4);
    // Nach dem ersten Satz sind die Legs im Satz zurückgesetzt
    expect(m.state.legResults.where((l) => l.setNo == 1).length, 2);
  });

  test('Undo und Letzte Aufnahme ersetzen', () {
    var m = newMatch();
    m = m.submitTotal(100).submitTotal(45);
    expect(m.undo().state.remaining, [401, 501]);
    final corrected = m.replaceLast((b) => b.submitTotal(54));
    expect(corrected.state.remaining, [401, 447]);
    expect(newMatch().undo, throwsA(isA<MatchStateError>()));
    // Undo eines Checkouts macht das Match wieder spielbar
    var f = newMatch(start: 40).submitDarts([d('D20')]);
    f = f.undo();
    expect(f.state.totalLegsWon, [0, 0]);
    expect(f.isFinished, isFalse);
  });

  test('Checkout-Validierung in Modus B (ungültige Checkouts verhindern)', () {
    var m = newMatch(start: 100);
    expect(() => m.submitTotal(100, dartsUsed: 1), throwsArgumentError);
    final done = m.submitTotal(100, dartsUsed: 2);
    expect(done.state.totalLegsWon[0], 1);
    expect(done.lastVisit!.dartsThrown, 2);
    expect(done.lastVisit!.darts, isNull, reason: 'keine erfundenen Einzeldarts');
  });

  test('Double Out: Rest 1 / ungültiges Finish führen zu Bust', () {
    var m = newMatch(start: 41);
    m = m.submitDarts([d('S20'), d('S20')]); // 41-40 = 1 -> Bust
    expect(m.lastVisit!.bust, isTrue);
    var n = newMatch(start: 40);
    n = n.submitDarts([d('S20'), d('S20')]);
    expect(n.lastVisit!.bust, isTrue);
    expect(n.state.remaining[0], 40);
  });

  test('Optimistische Nebenläufigkeit: zweiter Schreiber mit altem Stand scheitert', () {
    final base = newMatch();
    final v = base.version;
    final a = base.submitTotal(60, expectedVersion: v);
    expect(() => a.submitTotal(45, expectedVersion: v), throwsA(isA<MatchStateError>()));
    // Selber Stand, zweite Eingabe mit aktueller Version klappt
    expect(a.submitTotal(45, expectedVersion: a.version).version, 2);
  });

  test('JSON-Roundtrip erhält den Spielstand', () {
    var m = newMatch().submitTotal(100).submitDarts([d('T20'), d('T20'), d('T20')]);
    final r = X01Match.fromJson(m.toJson());
    expect(r.state.remaining, m.state.remaining);
    expect(r.visits.length, 2);
    expect(r.visits[1].darts, [d('T20'), d('T20'), d('T20')]);
    expect(r.visits[0].darts, isNull);
  });

  test('Korruptes Log wird erkannt', () {
    final m = newMatch().submitTotal(100).submitTotal(60);
    final json = m.toJson();
    (json['visits'] as List)[1]['startScore'] = 123;
    expect(() => X01Match.fromJson(json).state, throwsA(isA<MatchStateError>()));
  });

  test('Double In: Eröffnung wird getrackt', () {
    var m = newMatch(inMode: InMode.double);
    m = m.submitDarts([d('T20'), d('T20'), d('T20')]);
    expect(m.state.remaining[0], 501);
    expect(m.state.opened[0], isFalse);
    m = m.submitTotal(0);
    m = m.submitDarts([d('D10'), d('S20'), d('S20')]);
    expect(m.state.remaining[0], 441);
    expect(m.state.opened[0], isTrue);
  });

  test('Bull-Off im Entscheidungsleg', () {
    var m = newMatch(start: 40, format: const MatchFormat(legsToWinSet: 2));
    m = m.submitDarts([d('D20')]); // P0 gewinnt Leg 1
    m = m.submitDarts([d('D20')]); // P1 gewinnt Leg 2
    expect(m.isDeciderLeg, isTrue);
    m = m.withStarterOverride(3, 1);
    expect(m.state.currentPlayer, 1);
    expect(m.state.legStarter, 1);
    m = m.submitDarts([d('D20')]);
    expect(m.state.winnerIndex, 1);
  });

  test('Einzelspieler / Training', () {
    var m = newMatch(start: 40, players: 1, format: const MatchFormat(legsToWinSet: 1));
    m = m.submitTotal(0);
    expect(m.state.currentPlayer, 0);
    m = m.submitDarts([d('D20')]);
    expect(m.isFinished, isTrue);
  });

  test('Leg-Average', () {
    var m = newMatch().submitTotal(60).submitTotal(0).submitTotal(60);
    expect(m.legAverage(0), 60.0);
    expect(m.legAverage(1), 0.0);
  });
}

void draftTests() {
  test('Vorschau einer laufenden Aufnahme', () {
    final m = newMatch(start: 100);
    var pv = m.previewDraft([d('T20')]);
    expect(pv.remaining, 40);
    expect(pv.complete, isFalse);
    expect(pv.dartsLeft, 2);
    pv = m.previewDraft([d('T20'), d('D20')]);
    expect(pv.complete, isTrue);
    expect(pv.evaluation!.isCheckout, isTrue);
    pv = m.previewDraft([d('T20'), d('T20')]);
    expect(pv.evaluation!.isBust, isTrue);
    expect(pv.complete, isTrue);
    pv = m.previewDraft([d('S1'), d('S1'), d('S1')]);
    expect(pv.complete, isTrue);
    expect(pv.remaining, 97);
    expect(m.previewDraft([]).dartsLeft, 3);
  });
}
