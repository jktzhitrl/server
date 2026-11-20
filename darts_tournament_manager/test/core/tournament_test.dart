import 'dart:math';

import 'package:darts_tournament_manager/core/auth/permissions.dart';
import 'package:darts_tournament_manager/core/tournament/board_scheduler.dart';
import 'package:darts_tournament_manager/core/tournament/bracket.dart';
import 'package:darts_tournament_manager/core/tournament/group_stage.dart';
import 'package:darts_tournament_manager/core/tournament/participant.dart';
import 'package:darts_tournament_manager/core/tournament/round_robin.dart';
import 'package:darts_tournament_manager/core/tournament/seeding.dart';
import 'package:darts_tournament_manager/core/tournament/swiss.dart';
import 'package:flutter_test/flutter_test.dart';

List<Participant> players(int n, {Set<int> seeded = const {}}) => [
      for (var i = 1; i <= n; i++)
        Participant(id: 'p$i', name: 'Spieler $i', seed: seeded.contains(i) ? i : null),
    ];

/// Spielt einen Baum komplett durch; der Spieler mit der kleineren Nummer gewinnt.
void playOut(Bracket b) {
  var guard = 0;
  while (!b.isComplete && guard++ < 500) {
    final next = b.playable;
    if (next.isEmpty) break;
    final m = next.first;
    final ids = m.playerIds..sort((x, y) => int.parse(x.substring(1)).compareTo(int.parse(y.substring(1))));
    b.reportResult(m.id, ids.first);
  }
}

void main() {
  group('Seeding', () {
    test('Setzreihenfolge', () {
      expect(seedOrder(2), [1, 2]);
      expect(seedOrder(4), [1, 4, 2, 3]);
      expect(seedOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
      expect(seedOrder(16).take(4), [1, 16, 8, 9]);
      expect(() => seedOrder(6), throwsArgumentError);
    });
    test('Zweierpotenz', () {
      expect([1, 2, 3, 5, 8, 9].map(nextPowerOfTwo), [1, 2, 4, 8, 8, 16]);
    });
  });

  group('Single Elimination', () {
    test('Freilose bei ungerader Spielerzahl (5 Spieler)', () {
      final pos = bracketPositions(players(5, seeded: {1, 2, 3}), rng: Random(1));
      expect(pos.length, 8);
      expect(pos.where((p) => p == null).length, 3);
      final b = Bracket.singleElimination(pos);
      final byes = b.matches.where((m) => m.isBye).toList();
      expect(byes.length, 3);
      // Top-Gesetzte bekommen Freilose
      final byeWinners = byes.map((m) => m.winnerId).toSet();
      expect(byeWinners, {'p1', 'p2', 'p3'});
      // Nur ein Spiel in Runde 1 muss gespielt werden
      expect(b.playable.where((m) => m.round == 1).length, 1);
    });

    test('jeder Teilnehmer erscheint genau einmal; 8 Spieler -> 7 Spiele', () {
      final pos = bracketPositions(players(8), rng: Random(7));
      expect(pos.whereType<Participant>().map((p) => p.id).toSet().length, 8);
      final b = Bracket.singleElimination(pos);
      expect(b.matches.length, 7);
      expect(b.matches.where((m) => m.side == 'W' && m.round == 3).length, 1);
    });

    test('automatischer Rundenfortschritt bis zum Sieger', () {
      for (final n in [2, 3, 4, 5, 6, 7, 8, 11, 16, 23]) {
        final b = Bracket.singleElimination(bracketPositions(players(n), rng: Random(n)));
        playOut(b);
        expect(b.isComplete, isTrue, reason: 'n=$n');
        expect(b.championId, 'p1', reason: 'n=$n');
        // Anzahl echter Spiele = n-1
        final real = b.matches.where((m) => m.winnerId != null && !m.isBye).length;
        expect(real, n - 1, reason: 'n=$n');
      }
    });

    test('Setzplätze 1 und 2 treffen sich erst im Finale', () {
      final b = Bracket.singleElimination(
          bracketPositions(players(8, seeded: {1, 2, 3, 4, 5, 6, 7, 8}), rng: Random(3)));
      final final_ = b.roundMatches('W', 3).single;
      playOut(b);
      expect(final_.playerIds.toSet(), {'p1', 'p2'});
    });

    test('nächste Begegnung eines Spielers', () {
      final b = Bracket.singleElimination(
          bracketPositions(players(4, seeded: {1, 2, 3, 4}), rng: Random(0)));
      expect(b.nextMatchFor('p1')!.playerIds.toSet(), {'p1', 'p4'});
      b.reportResult(b.nextMatchFor('p1')!.id, 'p1');
      final n = b.nextMatchFor('p1');
      expect(n, isNull, reason: 'wartet auf Gegner im Finale');
      expect(b.isEliminated('p4'), isTrue);
      expect(b.isEliminated('p1'), isFalse);
    });

    test('ungültige Ergebniseingaben', () {
      final b = Bracket.singleElimination(bracketPositions(players(4), rng: Random(0)));
      final m = b.playable.first;
      expect(() => b.reportResult(m.id, 'fremd'), throwsA(isA<BracketError>()));
      final finalId = b.roundMatches('W', 2).single.id;
      expect(() => b.reportResult(finalId, 'p1'), throwsA(isA<BracketError>()));
      expect(() => b.reportResult('gibts-nicht', 'p1'), throwsA(isA<BracketError>()));
    });

    test('Korrektur nur solange Folgespiel offen', () {
      final b = Bracket.singleElimination(
          bracketPositions(players(4, seeded: {1, 2, 3, 4}), rng: Random(0)));
      final m1 = b.playable.first;
      b.reportResult(m1.id, m1.playerIds.first);
      b.reportResult(m1.id, m1.playerIds.last); // Korrektur erlaubt
      expect(b.match(m1.winnerToId!).a.playerId ?? b.match(m1.winnerToId!).b.playerId,
          m1.playerIds.last);
      // zweites Halbfinale + Finale spielen
      final m2 = b.playable.first;
      b.reportResult(m2.id, m2.playerIds.first);
      final fin = b.playable.single;
      b.reportResult(fin.id, fin.playerIds.first);
      expect(() => b.reportResult(m1.id, m1.playerIds.first), throwsA(isA<BracketError>()));
    });

    test('JSON-Roundtrip', () {
      final b = Bracket.singleElimination(bracketPositions(players(6), rng: Random(2)));
      b.reportResult(b.playable.first.id, b.playable.first.playerIds.first);
      final r = Bracket.fromJson(b.toJson());
      expect(r.matches.length, b.matches.length);
      expect(r.playable.map((m) => m.id), b.playable.map((m) => m.id));
    });
  });

  group('Double Elimination', () {
    test('Struktur für 8 Spieler: 7 WB + 6 LB + 2 GF', () {
      final b = Bracket.doubleElimination(bracketPositions(players(8), rng: Random(1)));
      expect(b.matches.where((m) => m.side == 'W').length, 7);
      expect(b.matches.where((m) => m.side == 'L').length, 6);
      expect(b.matches.where((m) => m.side == 'G').length, 2);
    });

    test('Komplettdurchlauf für 2..16 Spieler: Sieger, jeder genau zweimal besiegbar', () {
      for (final n in [2, 3, 4, 5, 6, 7, 8, 9, 12, 16]) {
        final b = Bracket.doubleElimination(bracketPositions(players(n), rng: Random(n)));
        playOut(b);
        expect(b.isComplete, isTrue, reason: 'n=$n');
        expect(b.championId, 'p1', reason: 'n=$n');
        // Niemand verliert öfter als zweimal
        final losses = <String, int>{};
        for (final m in b.matches) {
          if (m.loserId != null && !m.isBye) losses[m.loserId!] = (losses[m.loserId!] ?? 0) + 1;
        }
        for (final e in losses.entries) {
          expect(e.value <= 2, isTrue, reason: 'n=$n ${e.key}');
        }
        // Alle Spiele entschieden oder tot
        expect(b.matches.every((m) => m.isResolved), isTrue, reason: 'n=$n');
      }
    });

    test('Grand-Final-Reset: LB-Sieger gewinnt erstes Finale', () {
      final b = Bracket.doubleElimination(
          bracketPositions(players(4, seeded: {1, 2, 3, 4}), rng: Random(0)));
      // Spieler p1 gewinnt WB; p2 gewinnt über LB; im GF gewinnt p2 -> Reset
      var guard = 0;
      while (b.playable.any((m) => m.side != 'G') && guard++ < 50) {
        final m = b.playable.firstWhere((m) => m.side != 'G');
        final ids = m.playerIds..sort();
        b.reportResult(m.id, ids.first);
      }
      final g1 = b.match('G-r1-m0');
      expect(g1.isPlayable, isTrue);
      expect(g1.a.playerId, 'p1');
      b.reportResult(g1.id, g1.b.playerId!);
      expect(b.isComplete, isFalse);
      final g2 = b.match('G-r2-m0');
      expect(g2.isPlayable, isTrue);
      b.reportResult(g2.id, g2.a.playerId!);
      expect(b.isComplete, isTrue);
      expect(b.championId, 'p1');
    });

    test('Kein Reset, wenn Gewinnerbaum-Sieger das Finale gewinnt', () {
      final b = Bracket.doubleElimination(bracketPositions(players(4), rng: Random(5)));
      playOut(b);
      expect(b.match('G-r2-m0').dead, isTrue);
    });
  });

  group('Round Robin / Liga', () {
    test('jeder gegen jeden, gerade Anzahl', () {
      final ids = [for (var i = 1; i <= 6; i++) 'p$i'];
      final fx = RoundRobin.schedule(ids, rng: Random(1));
      expect(fx.length, 15);
      final pairs = fx.map((f) => ({f.homeId, f.awayId}.toList()..sort()).join('-')).toSet();
      expect(pairs.length, 15);
      expect(fx.map((f) => f.round).toSet().length, 5);
      // niemand spielt zweimal pro Runde
      for (var r = 1; r <= 5; r++) {
        final inRound = fx.where((f) => f.round == r).expand((f) => f.playerIds).toList();
        expect(inRound.length, inRound.toSet().length);
        expect(inRound.length, 6);
      }
    });
    test('ungerade Anzahl: Freilos pro Runde', () {
      final ids = [for (var i = 1; i <= 5; i++) 'p$i'];
      final fx = RoundRobin.schedule(ids, rng: Random(2));
      expect(fx.length, 10);
      final byes = RoundRobin.byes(fx, ids);
      expect(byes.length, 5);
      expect(byes.values.toSet().length, 5, reason: 'jeder genau einmal spielfrei');
    });
    test('Hin- und Rückrunde', () {
      final ids = ['a', 'b', 'c', 'd'];
      final fx = RoundRobin.schedule(ids, doubleRound: true, rng: Random(3));
      expect(fx.length, 12);
      expect(fx.map((f) => f.round).reduce(max), 6);
      for (final f in fx.where((f) => f.id.endsWith('-rueck'))) {
        final hin = fx.firstWhere((x) => x.id == f.id.replaceAll('-rueck', ''));
        expect(hin.homeId, f.awayId);
        expect(hin.awayId, f.homeId);
      }
    });
    test('Mindestens 2 Teilnehmer', () {
      expect(() => RoundRobin.schedule(['a']), throwsArgumentError);
    });
  });

  group('Gruppenplatzierungen', () {
    Fixture f(String h, String a, int hl, int al) => Fixture(
        id: '$h$a', round: 1, homeId: h, awayId: a, homeLegs: hl, awayLegs: al,
        winnerId: hl > al ? h : a);

    test('Punkte, Leg-Differenz', () {
      final rows = computeStandings(['a', 'b', 'c'], [
        f('a', 'b', 3, 1),
        f('b', 'c', 3, 2),
        f('c', 'a', 3, 0),
      ]);
      // je 1 Sieg: a(+2-3=-1... ) -> a: 3-1 gewonnen, 0-3 verloren: diff -1; b: 1-3, 3-2: diff -1; c: 2-3, 3-0: diff +2
      expect(rows.first.playerId, 'c');
      expect(rows.map((r) => r.points), [2, 2, 2]);
      expect(rows.map((r) => r.rank), [1, 2, 3]);
    });
    test('direkter Vergleich bei Gleichstand von genau zwei', () {
      final rows = computeStandings(['a', 'b', 'c'], [
        f('a', 'b', 3, 1), // a schlägt b
        f('c', 'a', 3, 0), // c schlägt a
        f('b', 'c', 2, 1), // b schlägt c
      ]);
      // Alle 2 Punkte; c hat +2 Legs, a und b je -1 mit 3 gewonnenen Legs -> direkter Vergleich: a vor b
      expect(rows.map((r) => r.playerId), ['c', 'a', 'b']);
    });
    test('Gruppen auslosen: balanciert, Gesetzte verteilt', () {
      final ps = players(10, seeded: {1, 2, 3, 4});
      final groups = GroupStage.draw(ps, groupCount: 4, rng: Random(1));
      expect(groups.length, 4);
      expect(groups.map((g) => g.playerIds.length).toList()..sort(), [2, 2, 3, 3]);
      final seeds = groups.map((g) => g.playerIds.where((id) => ['p1', 'p2', 'p3', 'p4'].contains(id)).length);
      expect(seeds.every((c) => c == 1), isTrue);
      expect(groups.expand((g) => g.playerIds).toSet().length, 10);
    });
    test('Gruppengröße konfigurierbar', () {
      final groups = GroupStage.draw(players(12), groupSize: 4, rng: Random(2));
      expect(groups.length, 3);
      expect(groups.every((g) => g.playerIds.length == 4), isTrue);
    });
    test('Qualifikation und K.-o.-Paarungen ohne Gruppen-Rückspiele', () {
      final groups = GroupStage.draw(players(16), groupCount: 4, rng: Random(4));
      final fx = GroupStage.fixtures(groups, rng: Random(4));
      expect(fx.length, 24);
      // höhere Nummer verliert
      for (final x in fx) {
        final h = int.parse(x.homeId.substring(1)), a = int.parse(x.awayId.substring(1));
        x.winnerId = h < a ? x.homeId : x.awayId;
        x.homeLegs = h < a ? 2 : 0;
        x.awayLegs = h < a ? 0 : 2;
      }
      expect(GroupStage.isComplete(fx), isTrue);
      final tables = GroupStage.standings(groups, fx);
      final q = GroupStage.qualifiers(tables, 2);
      expect(q.length, 8);
      final names = {for (final p in players(16)) p.id: p.name};
      final pos = GroupStage.knockoutPositions(q, names);
      expect(pos.length, 8);
      final groupOf = {for (final x in q) x.playerId: x.group};
      for (var i = 0; i < 4; i++) {
        expect(groupOf[pos[2 * i]!.id] != groupOf[pos[2 * i + 1]!.id], isTrue,
            reason: 'Paar $i derselbe Gruppe');
      }
      final b = Bracket.singleElimination(pos);
      playOut(b);
      expect(b.isComplete, isTrue);
    });
  });

  group('Schweizer System', () {
    test('Rundenzahl', () {
      expect([2, 4, 8, 9, 16].map(SwissSystem.recommendedRounds), [1, 2, 3, 4, 4]);
    });
    test('keine Rückspiele über mehrere Runden, Freilos nur einmal', () {
      final ids = [for (var i = 1; i <= 7; i++) 'p$i'];
      final played = <Fixture>[];
      final rng = Random(11);
      for (var round = 1; round <= 3; round++) {
        final state = SwissSystem.buildState(ids, played);
        final pairing = SwissSystem.pairRound(state, rng: rng);
        expect(pairing.bye, isNotNull);
        expect(pairing.pairs.length, 3);
        for (final (h, a) in pairing.pairs) {
          expect(played.any((f) => {f.homeId, f.awayId}.containsAll({h, a})), isFalse,
              reason: 'Rückspiel $h-$a in Runde $round');
          final win = int.parse(h.substring(1)) < int.parse(a.substring(1)) ? h : a;
          played.add(Fixture(
              id: '$round$h$a', round: round, homeId: h, awayId: a, winnerId: win,
              homeLegs: win == h ? 2 : 0, awayLegs: win == h ? 0 : 2));
        }
      }
      final byes = <String>[];
      for (var r = 1; r <= 3; r++) {
        final playing = played.where((f) => f.round == r).expand((f) => f.playerIds).toSet();
        byes.addAll(ids.where((i) => !playing.contains(i)));
      }
      expect(byes.toSet().length, byes.length);
      final table = SwissSystem.standings(ids, played);
      expect(table.first.points >= table.last.points, isTrue);
    });
  });

  group('Boards und Pausen', () {
    const sched = BoardScheduler(minRest: Duration(minutes: 5));
    final now = DateTime(2025, 1, 1, 20);
    test('weist freie Boards zu, keine Spieler doppelt', () {
      final ready = [
        const PendingMatch('m1', 1, ['a', 'b']),
        const PendingMatch('m2', 1, ['a', 'c']),
        const PendingMatch('m3', 1, ['d', 'e']),
      ];
      final boards = [
        const Board(id: 'b1', name: 'Board 1'),
        const Board(id: 'b2', name: 'Board 2'),
        const Board(id: 'b3', name: 'Board 3', currentMatchId: 'x'),
      ];
      final out = sched.assign(ready: ready, boards: boards, now: now);
      expect(out.map((e) => e.matchId), ['m1', 'm3']);
      expect(out.map((e) => e.boardId), ['b1', 'b2']);
    });
    test('Spielpause wird respektiert, laufende Spieler gesperrt', () {
      final ready = [
        const PendingMatch('m1', 1, ['a', 'b']),
        const PendingMatch('m2', 1, ['c', 'd']),
        const PendingMatch('m3', 2, ['e', 'f']),
      ];
      final out = sched.assign(
        ready: ready,
        boards: [const Board(id: 'b1', name: 'B1'), const Board(id: 'b2', name: 'B2')],
        playingNow: {'c'},
        lastFinished: {'a': now.subtract(const Duration(minutes: 2))},
        now: now,
      );
      expect(out.map((e) => e.matchId), ['m3']);
      final rest = sched.restingPlayers({'a': now.subtract(const Duration(minutes: 2))}, now: now);
      expect(rest['a'], const Duration(minutes: 3));
    });
    test('kein freies Board -> keine Zuweisung', () {
      expect(
          sched.assign(
              ready: [const PendingMatch('m1', 1, ['a', 'b'])],
              boards: [const Board(id: 'b1', name: 'B1', currentMatchId: 'x')]),
          isEmpty);
    });
  });

  group('Rollen und Berechtigungen', () {
    test('Matrix', () {
      expect(can(Role.spectator, Permission.viewPublicTournament), isTrue);
      expect(can(Role.spectator, Permission.enterScores), isFalse);
      expect(can(Role.player, Permission.joinTournament), isTrue);
      expect(can(Role.player, Permission.enterScores), isFalse);
      expect(can(Role.scorer, Permission.enterScores), isTrue);
      expect(can(Role.scorer, Permission.confirmResult), isFalse);
      expect(can(Role.scorer, Permission.runDraw), isFalse);
      expect(can(Role.director, Permission.runDraw), isTrue);
      expect(can(Role.director, Permission.confirmResult), isTrue);
      expect(can(Role.director, Permission.correctResult), isTrue);
      expect(can(Role.director, Permission.manageRoles), isFalse);
      expect(can(Role.director, Permission.createTournament), isFalse);
      for (final p in Permission.values) {
        expect(can(Role.admin, p), isTrue);
      }
    });
    test('Rechte sind monoton nach Rolle (Admin >= Leitung >= Schreiber >= Spieler)', () {
      final order = [Role.spectator, Role.player, Role.scorer, Role.director, Role.admin];
      for (var i = 1; i < order.length; i++) {
        for (final p in Permission.values) {
          if (can(order[i - 1], p)) {
            expect(can(order[i], p), isTrue, reason: '${order[i]} verliert $p');
          }
        }
      }
    });
    test('effektive Rolle und Rollenvergabe', () {
      expect(effectiveRole(Role.player, Role.director), Role.director);
      expect(effectiveRole(Role.admin, Role.player), Role.admin);
      expect(effectiveRole(Role.player, null), Role.player);
      expect(canGrantRole(Role.admin, Role.admin), isTrue);
      expect(canGrantRole(Role.director, Role.scorer), isTrue);
      expect(canGrantRole(Role.director, Role.director), isFalse);
      expect(canGrantRole(Role.scorer, Role.player), isFalse);
    });
  });
}
