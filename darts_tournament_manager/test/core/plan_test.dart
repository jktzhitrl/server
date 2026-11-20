import 'dart:convert';
import 'dart:math';

import 'package:darts_tournament_manager/core/tournament/participant.dart';
import 'package:darts_tournament_manager/core/tournament/tournament_plan.dart';
import 'package:flutter_test/flutter_test.dart';

List<Participant> ps(int n, {int seeds = 0}) => [
      for (var i = 1; i <= n; i++)
        Participant(id: 'p$i', name: 'S$i', seed: i <= seeds ? i : null),
    ];

/// Spielt alles durch, kleinere Nummer gewinnt. Gibt Anzahl gespielter Spiele zurück.
int playAll(TournamentPlan plan, {Random? rng}) {
  var played = 0;
  var guard = 0;
  while (!plan.isComplete && guard++ < 1000) {
    final next = plan.playable;
    if (next.isEmpty) break;
    final m = next.first;
    final ids = [...m.playerIds]..sort((a, b) => int.parse(a.substring(1)).compareTo(int.parse(b.substring(1))));
    plan.reportResult(m.id, ids.first, legsA: m.aId == ids.first ? 3 : 1, legsB: m.aId == ids.first ? 1 : 3, rng: rng);
    played++;
  }
  return played;
}

void main() {
  test('K.-o.: komplett, Auslosung manuell anpassbar bis zum ersten Ergebnis', () {
    final plan = TournamentPlan.draw(TournamentFormat.singleElimination, ps(8, seeds: 8),
        rng: Random(1));
    expect(plan.playable.length, 4);
    final before = plan.positions.toList();
    plan.swapPositions(0, 2);
    expect(plan.positions[0], before[2]);
    expect(plan.positions[2], before[0]);
    final first = plan.playable.first;
    plan.reportResult(first.id, first.aId);
    expect(() => plan.swapPositions(0, 1), throwsStateError);
    playAll(plan);
    expect(plan.isComplete, isTrue);
    expect(plan.championId, isNotNull);
  });

  test('Doppel-K.-o. mit 6 Spielern', () {
    final plan =
        TournamentPlan.draw(TournamentFormat.doubleElimination, ps(6), rng: Random(2));
    playAll(plan);
    expect(plan.championId, 'p1');
  });

  test('Round Robin & Liga', () {
    final rr = TournamentPlan.draw(TournamentFormat.roundRobin, ps(5), rng: Random(3));
    expect(playAll(rr), 10);
    expect(rr.championId, 'p1');
    expect(rr.tables().single.first.points, 8);
    final liga = TournamentPlan.draw(TournamentFormat.league, ps(4), rng: Random(3));
    expect(playAll(liga), 12);
    expect(liga.isComplete, isTrue);
  });

  test('Gruppenphase -> automatische K.-o.-Runde', () {
    final plan = TournamentPlan.draw(TournamentFormat.groupsKnockout, ps(12, seeds: 4),
        options: const PlanOptions(groupCount: 4, groupSize: null, advancePerGroup: 2),
        rng: Random(4));
    expect(plan.phase, PlanPhase.groups);
    expect(plan.groups.length, 4);
    final groupMatches = plan.fixtures.length;
    var played = 0;
    while (plan.phase == PlanPhase.groups) {
      final m = plan.playable.first;
      final ids = [...m.playerIds]..sort();
      plan.reportResult(m.id, ids.first, legsA: 3, legsB: 0);
      played++;
      expect(played <= groupMatches, isTrue);
    }
    expect(plan.phase, PlanPhase.knockout);
    expect(plan.bracket!.matches.where((m) => m.round == 1 && m.side == 'W').length, 4);
    playAll(plan);
    expect(plan.isComplete, isTrue);
    expect(plan.championId, isNotNull);
  });

  test('Gruppen: manueller Tausch', () {
    final plan = TournamentPlan.draw(TournamentFormat.groupsKnockout, ps(8),
        options: const PlanOptions(groupCount: 2, groupSize: null), rng: Random(5));
    final a = plan.groups[0].playerIds.first;
    final b = plan.groups[1].playerIds.first;
    plan.swapGroupMembers(a, b);
    expect(plan.groups[0].playerIds.contains(b), isTrue);
    expect(plan.groups[1].playerIds.contains(a), isTrue);
    expect(plan.fixtures.every((f) => plan.groups[f.group!].playerIds.contains(f.homeId)), isTrue);
  });

  test('Schweizer System: Folgerunden werden automatisch gepaart', () {
    final plan = TournamentPlan.draw(TournamentFormat.swiss, ps(8),
        options: const PlanOptions(swissRounds: 3), rng: Random(6));
    expect(plan.swissRound, 1);
    expect(plan.playable.length, 4);
    playAll(plan, rng: Random(6));
    expect(plan.swissRound, 3);
    expect(plan.isComplete, isTrue);
    expect(plan.fixtures.length, 12);
    // keine Rückspiele
    final pairs = plan.fixtures.map((f) => ({f.homeId, f.awayId}.toList()..sort()).join('-'));
    expect(pairs.toSet().length, pairs.length);
  });

  test('JSON-Roundtrip mitten im Turnier', () {
    final plan = TournamentPlan.draw(TournamentFormat.groupsKnockout, ps(8),
        options: const PlanOptions(groupCount: 2, groupSize: null), rng: Random(7));
    final m = plan.playable.first;
    plan.reportResult(m.id, m.aId);
    final copy = TournamentPlan.fromJson(jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>);
    expect(copy.fixtures.where((f) => f.isPlayed).length, 1);
    expect(copy.groups.length, 2);
    expect(copy.playable.length, plan.playable.length);
  });

  test('Eingabefehler', () {
    expect(() => TournamentPlan.draw(TournamentFormat.singleElimination, ps(1)), throwsArgumentError);
    expect(() => TournamentPlan.draw(TournamentFormat.friendly, ps(2)), throwsArgumentError);
    final plan = TournamentPlan.draw(TournamentFormat.roundRobin, ps(3));
    expect(() => plan.reportResult(plan.playable.first.id, 'fremd'), throwsArgumentError);
    expect(() => plan.reportResult('x', 'p1'), throwsArgumentError);
  });

  test('Nächste Begegnung für Spieler', () {
    final plan = TournamentPlan.draw(TournamentFormat.singleElimination, ps(4, seeds: 4), rng: Random(8));
    expect(plan.nextMatchFor('p1')!.playerIds.toSet(), {'p1', 'p4'});
  });
}
