import 'dart:math';

import 'package:darts_tournament_manager/core/auth/permissions.dart';
import 'package:darts_tournament_manager/core/models/dart_throw.dart';
import 'package:darts_tournament_manager/core/models/rules.dart';
import 'package:darts_tournament_manager/core/tournament/participant.dart';
import 'package:darts_tournament_manager/core/tournament/tournament_plan.dart';
import 'package:darts_tournament_manager/data/local_repository.dart';
import 'package:darts_tournament_manager/data/models.dart';
import 'package:darts_tournament_manager/data/repository.dart';
import 'package:darts_tournament_manager/data/services.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser user(String uid, Role role) => AppUser(uid: uid, displayName: uid, role: role);

void main() {
  late LocalRepository repo;
  late TournamentService svc;
  final admin = user('admin', Role.admin);
  final scorer = user('sc', Role.scorer);
  final player = user('pl', Role.player);

  setUp(() {
    repo = LocalRepository();
    svc = TournamentService(repo);
  });

  Future<TournamentRecord> tournament({TournamentFormat f = TournamentFormat.singleElimination, int n = 4}) async {
    var t = await svc.create(admin,
        name: 'Test', format: f, gameType: GameType.x301,
        rules: const X01Rules(format: MatchFormat(legsToWinSet: 1)));
    for (var i = 1; i <= n; i++) {
      t = await svc.addParticipant(admin, t, Participant(id: 'p$i', name: 'S$i', seed: i));
    }
    return t;
  }

  test('nur Admin darf Turniere anlegen', () async {
    expect(
        () => svc.create(player,
            name: 'x', format: TournamentFormat.roundRobin, gameType: GameType.x501, rules: const X01Rules()),
        throwsA(isA<PermissionDenied>()));
    final t = await tournament();
    expect(await repo.memberRole(t.id, 'admin'), Role.director);
    expect(t.inviteCode.length, 6);
  });

  test('Einladungscode und Beitritt', () async {
    var t = await svc.create(admin,
        name: 'Abend', format: TournamentFormat.roundRobin, gameType: GameType.x501, rules: const X01Rules());
    final found = await repo.findTournamentByInvite(t.inviteCode.toLowerCase());
    expect(found?.id, t.id);
    final pl = await repo.savePlayer(const PlayerProfile(id: 'pl1', name: 'Anna', uid: 'pl'));
    t = await svc.join(player, found!, pl);
    expect(t.registrations.single.name, 'Anna');
    expect(await repo.memberRole(t.id, 'pl'), Role.player);
    // doppelter Beitritt ändert nichts
    final again = await svc.join(player, t, pl);
    expect(again.registrations.length, 1);
    expect(await repo.findTournamentByInvite('XXXXXX'), isNull);
  });

  test('Rollen: Auslosung nur durch Leitung/Admin; Veröffentlichung nötig zum Start', () async {
    var t = await tournament();
    await repo.setMember(t.id, const TournamentMember('sc', 'sc', Role.scorer));
    expect(() => svc.draw(player, t), throwsA(isA<PermissionDenied>()));
    expect(() => svc.draw(scorer, t), throwsA(isA<PermissionDenied>()));
    t = await svc.draw(admin, t, rng: Random(1));
    expect(t.status, TournamentStatus.drawn);
    expect(t.published, isFalse);
    expect(() => svc.startMatch(admin, t, t.plan!.playable.first), throwsStateError);
    t = await svc.publish(admin, t);
    expect(t.status, TournamentStatus.running);
    // Nach Veröffentlichung keine Änderung der Auslosung
    expect(() => svc.savePlanEdit(admin, t, (p) => p.swapPositions(0, 1)), throwsStateError);
  });

  test('voller Ablauf: starten, Schreiber, Bestätigung, automatische nächste Runde', () async {
    var t = await tournament();
    await repo.setMember(t.id, const TournamentMember('sc', 'sc', Role.scorer));
    t = await svc.draw(admin, t, rng: Random(2));
    t = await svc.publish(admin, t);

    var guard = 0;
    while (!t.plan!.isComplete && guard++ < 10) {
      final pm = t.plan!.playable.first;
      final m = await svc.startMatch(admin, t, pm, boardId: 'b1', scorerUid: 'sc');
      t = (await repo.watchTournament(t.id).first)!;
      expect(t.boards.first.currentMatchId, m.id);
      // Spieler 0 gewinnt mit 301 in einem Leg: 180, 121 (Checkout T20 T11 D14)
      var cur = m;
      cur = await repo.updateMatch(cur.id, (c) => c.copyWith(
          x01: c.x01!.submitDarts([DartThrow.parse('T20'), DartThrow.parse('T20'), DartThrow.parse('T20')])), expectedVersion: cur.version);
      cur = await repo.updateMatch(cur.id, (c) => c.copyWith(x01: c.x01!.submitTotal(0)), expectedVersion: cur.version);
      cur = await repo.updateMatch(cur.id, (c) => c.copyWith(
          x01: c.x01!.submitDarts([DartThrow.parse('T20'), DartThrow.parse('T11'), DartThrow.parse('D14')])), expectedVersion: cur.version);
      expect(cur.isFinished, isTrue);
      await expectLater(() => svc.confirmResult(scorer, cur), throwsA(isA<PermissionDenied>()));
      cur = await svc.submitResult(scorer, cur);
      expect(cur.status, MatchStatus.awaitingConfirmation);
      t = (await svc.confirmResult(admin, cur))!;
      expect(t.boards.first.currentMatchId, isNull, reason: 'Board frei');
    }
    expect(t.plan!.isComplete, isTrue);
    expect(t.status, TournamentStatus.finished);
    expect(t.plan!.championId, isNotNull);
  });

  test('gleichzeitige Ergebniseingaben: zweiter Schreiber mit altem Stand wird abgelehnt', () async {
    final m = await repo.createMatch(MatchFactory.create(
      gameType: GameType.x501,
      players: const [MatchPlayer('a', 'A'), MatchPlayer('b', 'B')],
    ));
    final v0 = m.version;
    final a = await repo.updateMatch(m.id, (c) => c.copyWith(x01: c.x01!.submitTotal(100)), expectedVersion: v0);
    expect(a.version, v0 + 1);
    await expectLater(
        repo.updateMatch(m.id, (c) => c.copyWith(x01: c.x01!.submitTotal(45)), expectedVersion: v0),
        throwsA(isA<VersionConflict>()));
    final stored = (await repo.watchMatch(m.id).first)!;
    expect(stored.x01!.visits.length, 1, reason: 'die abgelehnte Eingabe wurde nicht gespeichert');
    // Wiederherstellung nach Verbindungsabbruch: neuer Stand lesen, dann erneut senden
    final b = await repo.updateMatch(m.id, (c) => c.copyWith(x01: c.x01!.submitTotal(45)), expectedVersion: stored.version);
    expect(b.x01!.state.remaining, [401, 456]);
  });

  test('parallele Eingaben mit gleicher Version: genau eine gewinnt', () async {
    final m = await repo.createMatch(MatchFactory.create(
      gameType: GameType.x501,
      players: const [MatchPlayer('a', 'A'), MatchPlayer('b', 'B')],
    ));
    final results = await Future.wait([
      for (var i = 0; i < 5; i++)
        repo
            .updateMatch(m.id, (c) => c.copyWith(x01: c.x01!.submitTotal(60)), expectedVersion: 0)
            .then((_) => true)
            .catchError((_) => false),
    ]);
    expect(results.where((r) => r).length, 1);
    expect((await repo.watchMatch(m.id).first)!.x01!.visits.length, 1);
  });

  test('Turnierversion schützt vor widersprüchlichem Überschreiben', () async {
    final t = await tournament();
    await repo.saveTournament(t.copyWith(name: 'A'));
    await expectLater(repo.saveTournament(t.copyWith(name: 'B')), throwsA(isA<VersionConflict>()));
  });

  test('Streams liefern Live-Updates', () async {
    final m = await repo.createMatch(MatchFactory.create(
      gameType: GameType.x501,
      players: const [MatchPlayer('a', 'A'), MatchPlayer('b', 'B')],
    ));
    final seen = <int>[];
    final sub = repo.watchMatch(m.id).listen((r) => seen.add(r!.x01!.visits.length));
    await Future<void>.delayed(Duration.zero);
    await repo.updateMatch(m.id, (c) => c.copyWith(x01: c.x01!.submitTotal(60)));
    await repo.updateMatch(m.id, (c) => c.copyWith(x01: c.x01!.submitTotal(60)));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, [0, 1, 2]);
  });

  test('Persistenz: Export/Import erhält Turnier und Begegnungen', () async {
    final t = await tournament();
    await svc.draw(admin, (await repo.watchTournament(t.id).first)!, rng: Random(3));
    await repo.createMatch(MatchFactory.create(
      gameType: GameType.cricket,
      players: const [MatchPlayer('a', 'A'), MatchPlayer('b', 'B')],
    ));
    final copy = LocalRepository(initialJson: repo.exportJson());
    final t2 = (await copy.watchTournament(t.id).first)!;
    expect(t2.plan!.bracket!.matches.length, 3);
    expect((await copy.watchMatches().first).single.gameType, GameType.cricket);
    // beschädigte Daten führen nicht zum Absturz
    expect(await LocalRepository(initialJson: '{kaputt').watchTournaments().first, isEmpty);
  });

  test('Boardzuweisung berücksichtigt Pausen und laufende Spiele', () async {
    var t = await tournament(n: 4);
    t = await svc.draw(admin, t, rng: Random(4));
    t = await svc.publish(admin, t);
    final sug = await svc.suggestAssignments(t);
    expect(sug.length, 2, reason: '2 Boards, 2 spielbare Halbfinals');
    await svc.startMatch(admin, t, t.plan!.playable.first, boardId: 'b1');
    t = (await repo.watchTournament(t.id).first)!;
    final sug2 = await svc.suggestAssignments(t);
    expect(sug2.length, 1);
    expect(sug2.single.boardId, 'b2');
    // gleiche Begegnung nicht zweimal starten
    expect(() => svc.startMatch(admin, t, t.plan!.playable.first), throwsStateError);
  });

  test('Statistiken aus Begegnungen', () async {
    var m = MatchFactory.create(
      gameType: GameType.x301,
      players: const [MatchPlayer('a', 'A'), MatchPlayer('b', 'B')],
      rules: const X01Rules(format: MatchFormat(legsToWinSet: 1)),
    );
    m = await repo.createMatch(m);
    m = await repo.updateMatch(m.id, (c) => c.copyWith(x01: c.x01!.submitTotal(180)));
    m = await repo.updateMatch(m.id, (c) => c.copyWith(x01: c.x01!.submitTotal(26)));
    m = await repo.updateMatch(m.id, (c) => c.copyWith(x01: c.x01!.submitTotal(121, dartsUsed: 3, checkoutAttempts: 1)));
    final s = StatsService.forPlayer('a', [m]);
    expect(s.count180, 1);
    expect(s.highestCheckout, 121);
    expect(s.matchesWon, 1);
    expect(s.checkoutRate, 1.0);
    expect(StatsService.forPlayer('b', [m]).matchesLost, 1);
  });

  test('Match-JSON-Roundtrip für Cricket und Around the Clock', () {
    final c = MatchFactory.create(
        gameType: GameType.cricket, players: const [MatchPlayer('a', 'A'), MatchPlayer('b', 'B')]);
    final c2 = MatchRecord.fromJson(c.copyWith(cricket: c.cricket!.addDart(DartThrow.parse('T20'))).toJson());
    expect(c2.cricket!.state.marks[0][20], 3);
    final k = MatchFactory.create(
        gameType: GameType.aroundTheClock, players: const [MatchPlayer('a', 'A')]);
    final k2 = MatchRecord.fromJson(k.copyWith(clock: k.clock!.addDart(DartThrow.parse('S1'))).toJson());
    expect(k2.clock!.state.progress[0], 1);
  });
}
