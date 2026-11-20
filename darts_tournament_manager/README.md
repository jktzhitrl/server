# Darts Tournament Manager Pro

Plattformübergreifende Darts-Turniersoftware (Flutter + Firebase) für private Dartabende, Vereine,
Ligen und größere Turniere – mit Live-Scoreboard, regelbasiertem Checkout-System, Turnierauslosung
und Echtzeit-Ansicht für alle Spieler auf dem eigenen Gerät.

> **Stand: 0.1.0 – Phasen 1–6 sind als lauffähiger, getesteter Code vorhanden.**
> Was bewusst noch fehlt oder nur teilweise umgesetzt ist, steht ehrlich unter
> [Bekannte Einschränkungen](#bekannte-einschränkungen).

## Funktionen

| Bereich | Umfang |
|---|---|
| Spielmodi | 301, 501, 701, 1001, Cricket (auch Cut-Throat), Around the Clock, Training |
| Regeln | Single/Double/Master In & Out, Best of 1–11, Legs **und** Sätze, wechselnder oder fester Anwurf, Bull-Off im Entscheidungsleg – pro Turnier oder Begegnung |
| Eingabe | **Modus A:** jeder Dart einzeln (interaktive Dartscheibe oder Tasten, Live-Zwischenstand der Aufnahme) · **Modus B:** nur Summe, optional Dartzahl/Doppelversuche · Undo, letzte Aufnahme bearbeiten, Pause, automatischer Spielerwechsel, Bust- und Checkout-Prüfung |
| Checkout | regelbasierter Algorithmus (alle 1–3-Dart-Wege, Double/Master/Single Out), Varianten *Standard, Wenigste Darts, Lieblingsdoppel, Sichere Route, Alternative*, berücksichtigt die verbleibenden Darts der Aufnahme |
| Statistik | 3-Dart-Ø, First-9, 180/140+/100+, Checkout-Quote/-Höchstwert/-Ø, Doppelquote je Feld, bestes/schlechtestes Leg, Siege/Niederlagen – je Spiel, Turnier, Karriere; nicht berechenbare Werte erscheinen als **„n/v“** statt erfundener Zahlen |
| Turniere | K.-o., Doppel-K.-o. (mit Grand-Final-Reset), Jeder gegen Jeden, Gruppen + K.-o., Schweizer System, Liga (Hin-/Rückrunde), Freundschaftsspiele |
| Auslosung | zufällig oder gesetzt, automatische Freilose, konfigurierbare Gruppengröße, **Prüfen/Tauschen vor Veröffentlichung**, automatischer Rundenfortschritt, Boards und Spielpausen |
| Rollen | Administrator, Turnierleitung, Schreiber/Caller, Spieler, Zuschauer (global und pro Turnier) |
| Live | Scoreboard auf allen Geräten in Echtzeit, TV-/Beamer-Vollbildmodus, Spielerportal, Einladungslink + QR-Code |

## Schnellstart (ohne Server, Demo-Modus)

```bash
cd darts_tournament_manager
flutter pub get
flutter run -d chrome          # oder: windows / macos / linux / Android-Gerät / iOS-Simulator
```

Ohne Firebase-Konfiguration startet die App im **Demo-Modus**: Daten liegen lokal auf dem Gerät,
Anmeldung erfolgt mit Name und frei wählbarer Rolle (Einstellungen → „Rolle wechseln“).
Voraussetzung: Flutter ≥ 3.27 (getestet mit der Vorabversion 3.51).

## Mit Firebase (Echtzeit, Konten, mehrere Geräte)

Kurzfassung – die Schritt-für-Schritt-Anleitung steht in [`docs/FIREBASE_SETUP.md`](docs/FIREBASE_SETUP.md):

1. Firebase-Projekt anlegen, **Authentication (E-Mail/Passwort)** und **Cloud Firestore** aktivieren.
2. Web-App registrieren und die Konfigurationswerte per `--dart-define` übergeben:
   ```bash
   flutter run -d chrome \
     --dart-define=FIREBASE_API_KEY=… --dart-define=FIREBASE_APP_ID=… \
     --dart-define=FIREBASE_MESSAGING_SENDER_ID=… --dart-define=FIREBASE_PROJECT_ID=… \
     --dart-define=FIREBASE_AUTH_DOMAIN=… --dart-define=FIREBASE_STORAGE_BUCKET=…
   ```
3. `cp .firebaserc.example .firebaserc`, Projekt-ID eintragen, dann `firebase deploy --only firestore,hosting`.
4. Ersten Administrator festlegen (Firestore-Konsole: `users/{uid}.role = "admin"`).

## Projektstruktur

```
darts_tournament_manager/
├─ lib/
│  ├─ core/            Reines Dart – keine Flutter-/Firebase-Abhängigkeit, vollständig getestet
│  │  ├─ models/       Dart-Wurf, Regeln, IDs
│  │  ├─ x01/          Ein-/Auswurf-Regeln, Aufnahme-Auswertung, Match (Event-Sourcing)
│  │  ├─ checkout/     Checkout-Rechner
│  │  ├─ games/        Cricket, Around the Clock
│  │  ├─ stats/        Spielerstatistik
│  │  ├─ tournament/   Auslosung, Turnierbaum, Tabellen, Gruppen, Schweizer System, Boards, Plan
│  │  └─ auth/         Rollen und Berechtigungen
│  ├─ data/            Modelle, Repository-Schnittstelle, Local-/Firestore-Implementierung, Dienste
│  ├─ ui/              Theme, Bildschirme, Widgets (Dartscheibe, Scoreboard, Bracket, …)
│  ├─ bootstrap.dart   Start (Firebase oder Demo)
│  └─ app.dart         MaterialApp, Anmelde-Gate
├─ test/               core/ (Spiellogik), data/ (Dienste, Konflikte), ui/ (Widget-Tests)
├─ functions/          Cloud Functions (TypeScript) – serverseitig validierte Eingabe + Tests
├─ rules-tests/        Tests der Security Rules gegen den Firestore-Emulator
├─ tool/gen_vectors.dart   Testvektoren Dart → TypeScript (Paritätsprüfung)
├─ firestore.rules · firestore.indexes.json · firebase.json
├─ docs/               Architektur, Datenmodell, Firebase-Setup, Deployment
└─ android/ ios/ web/ windows/ macos/ linux/
```

## Tests

```bash
flutter test                                  # 130+ Tests: Kern, Daten, Widgets
cd functions && npm ci && npm test            # TypeScript-Port, 4.700 Paritätsvektoren aus Dart
cd rules-tests && npm ci && npm test          # Security Rules im Firestore-Emulator (Java nötig)
```

Abgedeckt sind u. a.: Punkteberechnung, Bust-Regeln, Single-/Double-/Master-Out, 1 Restpunkt bei Double Out,
ungültige Finish-Darts, Checkout-Berechnung (jede Route wird gegen die Regeln validiert), Legs und Sätze,
Auslosung, Freilose, Gruppenplatzierungen, K.-o.-Fortschritt, Statistik, gleichzeitige Eingaben
(Versionskonflikte), Rollen/Berechtigungen (Dart **und** Security Rules).

## CI/CD

GitHub Actions (`.github/workflows/`):

* `darts-ci.yml` – Analyse, Tests, Web-Build, Functions-Tests, Rules-Tests, Dart↔TS-Paritätsprüfung
* `darts-deploy-web.yml` – Web-Build und Firebase-Hosting-Deploy (Live bei `main`, Vorschau-Kanal bei PRs), optional Rules/Functions
* `darts-mobile-build.yml` – manueller Android-APK-/iOS-Build

Details: [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md). Es werden **keine** Zugangsdaten eingecheckt – alle Werte
liegen in GitHub-Secrets bzw. `--dart-define`.

## Dokumentation

* [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) – Schichten, Event-Sourcing, Konfliktschutz, Entscheidungen
* [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md) – Firestore-Schema und Security Rules
* [`docs/FIREBASE_SETUP.md`](docs/FIREBASE_SETUP.md) – Einrichtung Schritt für Schritt
* [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) – Web, Android, iOS, Desktop

## Bekannte Einschränkungen

Ehrlicher Stand dessen, was **nicht** (vollständig) umgesetzt oder nicht verifiziert ist:

* **Serverseitige Validierung ist optional zweistufig.** Standardmäßig schreibt die App per Firestore-Transaktion mit
  Versionsprüfung; die **Security Rules** erzwingen Rolle, Versionssprung und Plausibilität (Punkte 0–180, Darts 1–3,
  höchstens eine neue Aufnahme je Schreibvorgang). Die *vollständige* Regelprüfung (Bust, Checkout, Spielerreihenfolge)
  läuft zusätzlich in der Cloud Function `submitVisit` (Blaze-Tarif nötig). Die App ruft diese Function noch **nicht**
  automatisch auf – die Anbindung des Clients ist ein offener Punkt (siehe `docs/ARCHITECTURE.md`).
* **Turnierfortschritt** (Ergebnis bestätigen → nächste Runde) wird vom Client der Turnierleitung berechnet und per
  versioniertem Schreibvorgang gespeichert, nicht in einer Function.
* **Eingaben brauchen eine Verbindung** (Firestore-Transaktionen). Bei Abbruch wird die Eingabe *nicht* stillschweigend
  verworfen, sondern mit Hinweis abgelehnt; Lesen/Anzeigen funktioniert aus dem Cache, Streams verbinden sich automatisch neu.
* Legs, Sätze, Darts und Checkout-Versuche liegen **eingebettet im Match-Dokument** (atomar, < 1 MB) statt in eigenen
  Collections; eine `statistics`-Collection gibt es nicht – Statistiken werden aus den Matches berechnet.
* Profilbilder: aktuell Initialen-Avatare (kein Upload).
* Oberfläche nur auf Deutsch.
* Bei Cricket/Around the Clock gibt es noch keine Statistik (nur X01).
* Verifiziert wurden Web-Build, Analyse und alle Tests unter Linux. Android-/iOS-/Desktop-Builds wurden **nicht**
  ausgeführt (nur vorbereitet), ebenso der Betrieb gegen ein echtes Firebase-Projekt (die Rules laufen im Emulator).
