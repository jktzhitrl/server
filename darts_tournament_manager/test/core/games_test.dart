import 'package:darts_tournament_manager/core/games/around_the_clock.dart';
import 'package:darts_tournament_manager/core/games/cricket.dart';
import 'package:darts_tournament_manager/core/models/dart_throw.dart';
import 'package:flutter_test/flutter_test.dart';

DartThrow d(String s) => DartThrow.parse(s);

void main() {
  group('Cricket', () {
    CricketMatch newGame() => CricketMatch(playerIds: const ['a', 'b']);
    CricketMatch throwAll(CricketMatch m, List<String> ds) =>
        ds.fold(m, (acc, s) => acc.addDart(d(s)));

    test('Marks und Schließen', () {
      var m = throwAll(newGame(), ['T20', 'S19', 'Miss']);
      expect(m.state.marks[0][20], 3);
      expect(m.state.marks[0][19], 1);
      expect(m.state.points, [0, 0]);
      expect(m.state.currentPlayer, 1);
    });
    test('Punkten nur solange Gegner offen hat', () {
      var m = throwAll(newGame(), ['T20', 'T20', 'Miss']); // 3 Marks + 3 Punkte à 20
      expect(m.state.points[0], 60);
      // Gegner schließt 20 -> kein Punkten mehr
      m = throwAll(m, ['T20', 'Miss', 'Miss']);
      m = throwAll(m, ['T20', 'Miss', 'Miss']);
      expect(m.state.points[0], 60);
    });
    test('Bull: Single = 1 Mark, Bullseye = 2', () {
      var m = throwAll(newGame(), ['25', 'Bull', 'Miss']);
      expect(m.state.marks[0][25], 3);
    });
    test('Sieg: alles geschlossen und Punkte >= Gegner', () {
      var m = newGame();
      // a schließt alle Felder, b wirft nur Misses
      for (var round = 0; round < 3; round++) {
        m = throwAll(m, ['T20', 'T19', 'T18']);
        if (m.state.winnerIndex != null) break;
        m = throwAll(m, ['Miss', 'Miss', 'Miss']);
        m = throwAll(m, ['T17', 'T16', 'T15']);
        m = throwAll(m, ['Miss', 'Miss', 'Miss']);
      }
      m = throwAll(m, ['Bull', '25']);
      expect(m.state.winnerIndex, 0);
      expect(() => m.addDart(d('S1')), throwsStateError);
    });
    test('Undo und Versionskonflikt', () {
      var m = throwAll(newGame(), ['T20']);
      expect(m.undo().state.marks[0][20], 0);
      expect(() => m.addDart(d('S1'), expectedVersion: 0), throwsStateError);
    });
    test('Cut-Throat: Punkte gehen an Gegner', () {
      var m = CricketMatch(playerIds: const ['a', 'b'], cutThroat: true);
      m = m.addDart(d('T20')).addDart(d('T20')).addDart(d('Miss'));
      expect(m.state.points, [0, 60]);
    });
  });

  group('Around the Clock', () {
    test('Reihenfolge 1..20, Bull', () {
      var m = AroundTheClockMatch(playerIds: const ['a', 'b']);
      m = m.addDart(d('S1')).addDart(d('T2')).addDart(d('S5')); // 1 ok, 2 ok, 5 falsch
      expect(m.state.progress[0], 2);
      expect(m.state.currentPlayer, 1);
      m = m.addDart(d('Miss')).addDart(d('Miss')).addDart(d('Miss'));
      expect(m.state.currentPlayer, 0);
      expect(AroundTheClockMatch.targetLabel(20), 'Bull');
    });
    test('Solo bis zum Bull', () {
      var m = AroundTheClockMatch(playerIds: const ['a']);
      for (var n = 1; n <= 20; n++) {
        m = m.addDart(d('S$n'));
      }
      expect(m.state.winnerIndex, isNull);
      m = m.addDart(d('25'));
      expect(m.state.winnerIndex, 0);
      expect(m.state.currentPlayer, 0);
    });
    test('Skip-Ahead: Triple springt 3 weiter', () {
      var m = AroundTheClockMatch(playerIds: const ['a'], skipAhead: true);
      m = m.addDart(d('T1'));
      expect(m.state.progress[0], 3);
    });
    test('Undo', () {
      var m = AroundTheClockMatch(playerIds: const ['a']).addDart(d('S1'));
      expect(m.undo().state.progress[0], 0);
    });
  });
}
