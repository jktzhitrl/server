# Architektur

## Schichten

```
┌───────────────────────────── ui/ ─────────────────────────────┐
│ Screens, Widgets (Dartscheibe, Scoreboard, Bracket, Keypad)   │  Flutter, Provider
├──────────────────────────── data/ ────────────────────────────┤
│ Modelle · TournamentService · MatchFactory · StatsService     │  Anwendungslogik + Rollenprüfung
│ AppRepository (Schnittstelle)                                 │
│   ├─ LocalRepository      (Demo/Offline, Tests)               │
│   └─ FirestoreRepository  (Echtzeit, Transaktionen)           │
│ AuthService (Local | Firebase)                                │
├──────────────────────────── core/ ────────────────────────────┤
│ Reines Dart: Regeln, Match-Engine, Checkout, Statistik,       │  keine Flutter-/Firebase-Imports
│ Auslosung/Turnierlogik, Rollen                                │  → schnell & vollständig testbar
└───────────────────────────────────────────────────────────────┘
        Firebase:  Auth · Firestore + Security Rules · Functions · Hosting
```

Die Abhängigkeitsrichtung ist strikt `ui → data → core`. `core/` kennt weder Flutter noch Firebase;
dadurch laufen über 100 Tests ohne Emulator, und die Spiellogik lässt sich 1:1 nach TypeScript portieren
(siehe unten).

## Event-Sourcing im Match

Ein X01-Match (`core/x01/x01_match.dart`) ist **unveränderlich** und besteht aus Regeln, Spielern und einer
Liste von *Aufnahmen* (`Visit`). Der Spielstand (Restscore, wer ist dran, Legs, Sätze, Sieger) wird bei jedem
Zugriff per **Replay** aus diesem Log berechnet. Folgen:

* **Undo** = letzte Aufnahme entfernen; **Letzte bearbeiten** = entfernen und neu eingeben.
* Es gibt keine zweite, auseinanderlaufende Wahrheit; ein manipuliertes Log wird beim Replay erkannt
  (`MatchStateError: Inkonsistentes Visit-Log`).
* Jede Aufnahme trägt einen Zeitstempel, ihre Eingabeart und – nur in Modus A – die Einzeldarts.
  **Modus B erfindet keine Dartdaten**: `darts == null`, und davon abhängige Statistiken (Doppelquote je Feld,
  Dartverteilung) werden als „n/v“ gekennzeichnet.
* Die laufende Aufnahme (Modus A) liegt als `draft` im Match-Dokument und wird mit synchronisiert – alle Geräte
  sehen die aktuelle Aufnahme live.

### Konventionen der Statistik

* 3-Dart-Ø = Punkte ÷ gezählte Darts × 3; Bust = 0 Punkte, 3 gezählte Darts.
* „100+“ und „140+“ sind kumulativ (180er zählen mit), `180` separat.
* First-9 = erste drei Aufnahmen jedes Legs.
* Checkout-Versuch = jeder Dart, der geworfen wird, während der Rest mit **einem** Dart beendbar ist
  (aus Einzeldarts abgeleitet). In Modus B gibt der Schreiber die „Darts auf Doppel“ optional an;
  Checkouts ohne bekannte Versuchszahl gehen **nicht** in die Quote ein (und werden separat ausgewiesen).

## Checkout-Rechner

`CheckoutCalculator` enumeriert **alle** regelkonformen Wege mit ≤ 3 Darts (Summe = Rest, letzter Dart ein
gültiges Finish, kein früherer Dart bustet) in kanonischer Reihenfolge und bewertet sie mit einer Kostenfunktion
(weniger Darts ≫ gutes Abschlussdoppel ≫ hohe Triples als Setup). Eine kleine Tabelle bekannter Profi-Routen
(`_curated`) dient nur als Präferenz; der Test `jede Route ist regelkonform` prüft für **alle** Reste jedes
Out-Modus Summe, Finish-Dart und Bust-Freiheit, ein weiterer Test die Vorgabetabelle (170, 167, … 2).
Varianten: Standard, Wenigste Darts, Lieblingsdoppel, Sichere Route (nur Singles als Setup, kein Bull-Finish),
Alternative.

## Turnierlogik

* `Bracket` – ein gemeinsamer Graph aus Begegnungen mit `winnerTo`/`loserTo`-Verweisen für Single **und**
  Double Elimination. Freilose sind „tote“ Plätze; ein Fixpunkt-Algorithmus (`_settle`) löst Freilose auf und
  gibt Sieger/Verlierer weiter. Grand-Final-Reset wird bei Sieg des Verliererbaum-Gewinners freigeschaltet.
* `bracketPositions` – klassische Setzreihenfolge; Freilose gehen an die höchsten Setzplätze.
* `RoundRobin` – Kreisverfahren, Freilos je Runde bei ungerader Zahl, Hin-/Rückrunde mit getauschtem Heimrecht.
* `computeStandings` – Punkte → Leg-Differenz → gewonnene Legs → direkter Vergleich (bei genau zwei) → Setzliste.
* `GroupStage` – Snake-Verteilung gesetzter Spieler, K.-o.-Paarungen ohne Gruppen-Rückspiele in Runde 1.
* `SwissSystem` – Paarung nach Punkten mit Backtracking (keine Rückspiele), Freilos höchstens einmal, Buchholz.
* `TournamentPlan` – fasst das zusammen: Auslosung (Entwurf, manuell tauschbar), Ergebnisse, automatische
  Qualifikation (Gruppen → K.-o.) und automatische Folgerunden (Schweizer System); komplett serialisierbar.
* `BoardScheduler` – weist freien Boards spielbare Begegnungen zu; gesperrt sind Spieler in laufenden Spielen
  und Spieler innerhalb ihrer Mindestpause.

## Schutz vor gleichzeitigen, widersprüchlichen Eingaben

Alle veränderlichen Dokumente (`matches`, `tournaments`) tragen eine `version`:

1. Der Client liest den Stand (Version *n*) und schreibt mit `expectedVersion = n`.
2. `FirestoreRepository.updateMatch` führt das in einer **Transaktion** aus; weicht die Version ab, wird
   `VersionConflict` geworfen und nichts gespeichert (UI: „Spielstand wurde auf einem anderen Gerät geändert“).
3. Die **Security Rules** erzwingen zusätzlich `version == alt + 1` – auch ein manipulierter Client kann
   einen veralteten Stand nicht überschreiben.

Getestet in `test/data_test.dart` (parallele Eingaben: genau eine gewinnt) und `rules-tests/` (Emulator).

## Serverseitige Validierung (Cloud Function)

`functions/src/engine.ts` ist ein Port der Spielregeln. Die Function `submitVisit` prüft Anmeldung, Rolle,
Version und berechnet Bust/Checkout/Restscore **selbst** (Client-Werte werden nie übernommen). Damit der Port
nicht von der Dart-Logik abweicht, erzeugt `tool/gen_vectors.dart` ~4.700 Testfälle (alle Out-/In-Modi,
Checkouts, Busts, Fehlerfälle); `functions/test/engine.test.ts` vergleicht den Port Fall für Fall, und die
CI prüft, dass `vectors.json` aktuell ist.

**Offener Punkt:** Der Flutter-Client schreibt derzeit direkt (Rules + Version). Um die Function zum
alleinigen Schreibweg zu machen: `AppRepository` um `submitVisit` erweitern (`cloud_functions`), den Aufruf in
`ScoringScreen._apply` nutzen und in `firestore.rules` für `matches` das Schreiben der `x01`-Daten sperren.

## Entscheidungen

| Entscheidung | Begründung |
|---|---|
| Flutter + `provider`, keine zusätzliche State-Library | Zustand liegt in Streams (Firestore) und unveränderlichen Match-Objekten; wenige Abhängigkeiten |
| Match-Log eingebettet im Match-Dokument | atomar versionierbar, < 1 MB selbst für lange Matches, ein Listener pro Spiel |
| Konfiguration per `--dart-define` | kein generiertes `firebase_options.dart` mit Schlüsseln im Repository; CI-freundlich |
| Demo-Modus mit `LocalRepository` | App ist ohne Backend lauffähig und testbar; gleiche Versionsprüfung wie Firestore |
| `flutter/material.dart` | läuft auf allen stabilen Versionen (neuere Vorabversionen markieren den Import nur als veraltet) |
