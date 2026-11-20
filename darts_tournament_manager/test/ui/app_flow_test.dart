import 'package:darts_tournament_manager/app.dart';
import 'package:darts_tournament_manager/bootstrap.dart';
import 'package:darts_tournament_manager/core/auth/permissions.dart';
import 'package:darts_tournament_manager/core/models/rules.dart';
import 'package:darts_tournament_manager/data/auth_service.dart';
import 'package:darts_tournament_manager/data/local_repository.dart';
import 'package:darts_tournament_manager/core/tournament/tournament_plan.dart';
import 'package:darts_tournament_manager/data/models.dart';
import 'package:darts_tournament_manager/data/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wartet auf asynchrone Repository-Operationen (echte Microtasks) und zeichnet neu.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle();
}

Future<(AppServices, LocalRepository)> startApp(WidgetTester tester, {Size size = const Size(1000, 2000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = LocalRepository();
  final services = AppServices(repo: repo, auth: LocalAuthService(repo));
  await tester.pumpWidget(DartsApp(services: services));
  await settle(tester);
  return (services, repo);
}

Future<void> login(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('demoName')), name);
  await tester.tap(find.byKey(const Key('demoStart')));
  await settle(tester);
}

Future<void> newMatch(WidgetTester tester, {String opponent = 'Bob'}) async {
  await tester.tap(find.byKey(const Key('quickNewMatch')));
  await settle(tester);
  await tester.enterText(find.byKey(const Key('playerName1')), opponent);
  await tester.ensureVisible(find.byKey(const Key('startMatch')));
  await tester.tap(find.byKey(const Key('startMatch')));
  await settle(tester);
}

void main() {
  testWidgets('Anmeldung ohne Namen zeigt Fehler, mit Namen kommt das Dashboard', (tester) async {
    await startApp(tester);
    await tester.tap(find.byKey(const Key('demoStart')));
    await settle(tester);
    expect(find.text('Bitte einen Namen eingeben.'), findsOneWidget);
    await login(tester, 'Alice');
    expect(find.text('Hallo Alice'), findsOneWidget);
    expect(find.text('Meine nächsten Spiele'), findsOneWidget);
  });

  testWidgets('Zuschauer-Zugang ohne Namen', (tester) async {
    await startApp(tester);
    await tester.tap(find.byKey(const Key('spectatorStart')));
    await settle(tester);
    expect(find.text('Hallo Zuschauer'), findsOneWidget);
    // Zuschauer sehen keine Schaltfläche zum Spielstart
    expect(find.byKey(const Key('quickNewMatch')), findsNothing);
  });

  testWidgets('Modus B: Gesamtpunkte eingeben, Bust, Rückgängig', (tester) async {
    await startApp(tester);
    await login(tester, 'Alice');
    await newMatch(tester);
    expect(find.text('501'), findsNWidgets(2));
    await tester.tap(find.text('Summe'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('quick-100')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('key-ok')));
    await settle(tester);
    expect(find.text('401'), findsOneWidget);
    // Bob ist dran: 180
    await tester.tap(find.byKey(const Key('quick-180')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('key-ok')));
    await settle(tester);
    expect(find.text('321'), findsOneWidget);
    // Rückgängig stellt Bobs Stand wieder her
    await tester.tap(find.byKey(const Key('undo')));
    await settle(tester);
    expect(find.text('321'), findsNothing);
    expect(find.text('401'), findsOneWidget);
  });

  testWidgets('Modus A: drei Darts T20 = 180, Bust wird erkannt', (tester) async {
    await startApp(tester);
    await login(tester, 'Alice');
    await newMatch(tester);
    await tester.tap(find.text('Darts'));
    await settle(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Triple'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('dart-20')));
      await settle(tester);
    }
    expect(find.text('321'), findsOneWidget);
    expect(find.textContaining('Letzte 180', findRichText: true), findsOneWidget);
  });

  testWidgets('Zwischenstand der laufenden Aufnahme wird sofort angezeigt', (tester) async {
    await startApp(tester);
    await login(tester, 'Alice');
    await newMatch(tester);
    await tester.tap(find.text('Darts'));
    await settle(tester);
    await tester.tap(find.text('Triple'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('dart-20')));
    await settle(tester);
    expect(find.text('441'), findsOneWidget);
    expect(find.text('T20'), findsWidgets);
    // Letzten Dart zurücknehmen
    await tester.tap(find.byKey(const Key('undo')));
    await settle(tester);
    expect(find.text('441'), findsNothing);
  });

  testWidgets('Zuschauer können nicht eingeben', (tester) async {
    final (services, repo) = await startApp(tester);
    await tester.runAsync(() => services.auth.signInDemo('Zed', Role.spectator));
    await settle(tester);
    // Spiel von anderem Nutzer anlegen
    final m = (await tester.runAsync(() => repo.createMatch(MatchFactory.create(
      gameType: GameType.x501,
      players: const [MatchPlayer('a', 'Ann'), MatchPlayer('b', 'Ben')],
    ))))!;
    await tester.tap(find.text('Live'));
    await settle(tester);
    await tester.tap(find.text('Ann  –  Ben'));
    await settle(tester);
    await tester.tap(find.byTooltip('Eingabe'));
    await settle(tester);
    expect(find.textContaining('Nur Ansicht'), findsOneWidget);
    expect(m.version, 0);
    final undo = tester.widget<OutlinedButton>(find.byKey(const Key('undo')));
    expect(undo.onPressed, isNull);
  });

  testWidgets('Turnier: anlegen, Teilnehmer, auslosen, veröffentlichen, Einladung', (tester) async {
    final (_, repo) = await startApp(tester);
    await login(tester, 'Alice');
    await tester.tap(find.text('Turniere'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('newTournament')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('tournamentName')), 'Freitagsrunde');
    await tester.ensureVisible(find.byKey(const Key('createTournament')));
    await tester.tap(find.byKey(const Key('createTournament')));
    await settle(tester);
    expect(find.text('Freitagsrunde'), findsWidgets);

    for (final n in ['Anna', 'Ben', 'Cem', 'Dora', 'Emil']) {
      await tester.tap(find.byKey(const Key('addParticipant')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('participantName')), n);
      await tester.tap(find.byKey(const Key('participantAdd')));
      await settle(tester);
    }
    expect(find.text('Teilnehmer (5)'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('drawButton')));
    await tester.tap(find.byKey(const Key('drawButton')));
    await settle(tester);
    expect(find.textContaining('Freilose werden automatisch vergeben'), findsOneWidget);
    await tester.tap(find.byKey(const Key('drawConfirm')));
    await settle(tester);
    expect(find.textContaining('Entwurf'), findsWidgets);
    expect(find.text('Freilos'), findsNWidgets(3));

    // Vor Veröffentlichung sehen Zuschauer nichts; Leitung veröffentlicht
    await tester.ensureVisible(find.byKey(const Key('publishButton')));
    await tester.tap(find.byKey(const Key('publishButton')));
    await settle(tester);
    final t = (await tester.runAsync(() => repo.watchTournaments().first))!.single;
    expect(t.published, isTrue);
    expect(t.status, TournamentStatus.running);

    await tester.tap(find.text('Spielplan'));
    await settle(tester);
    expect(find.text('Halbfinale'), findsOneWidget);

    // Einladung mit QR-Code
    await tester.tap(find.byKey(const Key('inviteButton')));
    await settle(tester);
    expect(find.text('Code: ${t.inviteCode}'), findsOneWidget);
  });

  testWidgets('Beitritt per Einladungscode', (tester) async {
    final (services, repo) = await startApp(tester);
    await login(tester, 'Alice');
    final admin = (await tester.runAsync(() => repo.getUser('demo-alice')))!;
    final t = (await tester.runAsync(() => services.tournaments.create(admin,
        name: 'Offen', format: TournamentFormat.roundRobin, gameType: GameType.x501, rules: const X01Rules())))!;
    await tester.tap(find.text('Turniere'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('joinByCode')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('inviteCode')), t.inviteCode.toLowerCase());
    await tester.tap(find.byKey(const Key('joinConfirm')));
    await settle(tester);
    final updated = (await tester.runAsync(() => repo.watchTournament(t.id).first))!;
    expect(updated.registrations.map((p) => p.name), ['Alice']);
  });
}
