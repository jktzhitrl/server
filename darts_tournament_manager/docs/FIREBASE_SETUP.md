# Firebase einrichten

Voraussetzungen: Google-Konto, [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.27,
Node.js ≥ 20, optional Java (für Emulator-Tests), `npm i -g firebase-tools`.

## 1. Projekt und Dienste

1. In der [Firebase-Konsole](https://console.firebase.google.com) ein Projekt erstellen.
2. **Authentication → Anmeldemethode → E-Mail/Passwort** aktivieren.
   (Optional **Anonym** aktivieren, wenn Zuschauer ohne Konto öffentliche Turniere sehen sollen.)
3. **Firestore Database → Datenbank erstellen** (Produktionsmodus, Region z. B. `eur3`).
4. **Hosting** aktivieren (nur beim ersten `firebase deploy` nötig).
5. *(Optional, für Cloud Functions)* Tarif auf **Blaze** umstellen.

## 2. Web-App registrieren und Konfiguration holen

*Projekteinstellungen → Allgemein → Meine Apps → Web (`</>`)* registrieren. Die angezeigten Werte werden **nicht**
ins Repository geschrieben, sondern per `--dart-define` übergeben:

| dart-define | Wert aus der Konsole |
|---|---|
| `FIREBASE_API_KEY` | `apiKey` |
| `FIREBASE_APP_ID` | `appId` |
| `FIREBASE_MESSAGING_SENDER_ID` | `messagingSenderId` |
| `FIREBASE_PROJECT_ID` | `projectId` |
| `FIREBASE_AUTH_DOMAIN` | `authDomain` |
| `FIREBASE_STORAGE_BUCKET` | `storageBucket` |

```bash
flutter run -d chrome --dart-define=FIREBASE_API_KEY=… --dart-define=FIREBASE_APP_ID=… \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=… --dart-define=FIREBASE_PROJECT_ID=… \
  --dart-define=FIREBASE_AUTH_DOMAIN=… --dart-define=FIREBASE_STORAGE_BUCKET=…
```

Tipp: Alle Werte in einer lokalen, **nicht eingecheckten** Datei `dart-defines.json` ablegen und mit
`flutter run --dart-define-from-file=dart-defines.json` starten.

> Firebase-API-Schlüssel für Web sind keine Geheimnisse – geschützt wird über Security Rules und
> *Autorisierte Domains* (Authentication → Einstellungen). Sie gehören trotzdem nicht ins Repository.

**Android/iOS:** Dieselben Werte reichen (kein `google-services.json` nötig, weil `Firebase.initializeApp` die
Optionen aus `--dart-define` bekommt). Für Android/iOS-Apps in der Konsole zusätzlich eine App mit der
Bundle-ID `de.dartstm.darts_tournament_manager` registrieren und deren `appId` verwenden.

## 3. Rules, Indizes und Functions deployen

```bash
cp .firebaserc.example .firebaserc        # Projekt-ID eintragen
firebase deploy --only firestore          # Security Rules + Indizes
cd functions && npm ci && cd ..
firebase deploy --only functions          # optional (Blaze)
```

## 4. Ersten Administrator festlegen

1. In der App ein Konto registrieren (es startet immer als „Spieler“).
2. Firestore-Konsole → `users/<uid>` → Feld `role` auf `admin` setzen.
3. Ab jetzt vergibt dieser Admin in **Einstellungen → Benutzer & Rollen** alle weiteren Rollen und legt Turniere an.
   Die Turnierleitung eines Turniers wird beim Anlegen automatisch der Ersteller; weitere Schreiber/Leiter
   vergibt man in der Turnier-Übersicht („Rollen im Turnier“).

## 5. Lokal mit Emulatoren testen

```bash
firebase emulators:start --only firestore,auth
cd rules-tests && npm ci && npm test        # startet seinen eigenen Emulator
```

## Spieler einladen

Turnier öffnen → QR-Symbol: zeigt **Einladungscode** und **QR-Code** (Link `…/?join=CODE`). Wird die Web-App
unter einer festen Adresse betrieben, beim Build `--dart-define=APP_BASE_URL=https://dein-projekt.web.app/`
setzen. Öffnet ein Spieler den Link, erscheint nach der Anmeldung der Beitritts-Dialog.
