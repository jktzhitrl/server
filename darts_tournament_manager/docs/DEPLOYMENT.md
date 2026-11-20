# Bereitstellung

## Web (Firebase Hosting)

Manuell:

```bash
flutter build web --release --dart-define=… (siehe FIREBASE_SETUP.md) --dart-define=APP_BASE_URL=https://<projekt>.web.app/
firebase deploy --only hosting
```

Automatisch per GitHub Actions (`.github/workflows/darts-deploy-web.yml`):

1. Dienstkonto anlegen: Google Cloud Console → IAM → Dienstkonten → Rolle *Firebase Hosting Admin*
   (für Rules/Functions zusätzlich *Cloud Datastore Owner* bzw. *Firebase Admin* und *Cloud Functions Admin*),
   JSON-Schlüssel erzeugen. Alternativ `firebase init hosting:github` ausführen, das legt das Secret an.
2. Repository-Secrets setzen: `FIREBASE_SERVICE_ACCOUNT` (kompletter JSON-Inhalt), `FIREBASE_PROJECT_ID`,
   `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_AUTH_DOMAIN`,
   `FIREBASE_STORAGE_BUCKET`; optional Repository-Variable `APP_BASE_URL`.
3. Push auf `main` → Tests, Build, Deploy auf den Live-Kanal. Pull Requests erhalten einen Vorschau-Link (7 Tage).
4. *Actions → Darts Manager – Deploy → Run workflow* mit „deploy_backend“ deployt zusätzlich Rules, Indizes, Functions.

**GitHub Pages allein reicht nicht:** Es liefert nur statische Dateien. Für gemeinsame Live-Erfassung und
Anmeldung braucht die App das Firebase-Backend. (Die gebaute Web-App kann man dennoch auf Pages hosten – dann in
Firebase unter *Authentication → Autorisierte Domains* die Pages-Domain eintragen.)

## Android

* `minSdk` ist auf 23 gesetzt (Firebase-Anforderung); App-ID `de.dartstm.darts_tournament_manager`
  (in `android/app/build.gradle.kts` anpassen).
* Debug: `flutter run -d <gerät> --dart-define=…`
* Release-APK/AAB: Signierschlüssel anlegen (`android/key.properties`, siehe
  [Flutter-Doku](https://docs.flutter.dev/deployment/android)), dann `flutter build appbundle --release --dart-define=…`.
* CI: `darts-mobile-build.yml` baut eine (unsignierte Debug-signierte) APK als Artefakt.

## iOS / macOS

* Benötigt macOS mit Xcode. Bundle-ID in Xcode (`Runner` → Signing & Capabilities) setzen.
* `flutter build ios --release --dart-define=…`, Archivieren und Hochladen über Xcode/Transporter.
* CI: `darts-mobile-build.yml` baut ohne Code-Signing (Prüfung der Kompilierbarkeit); für TestFlight werden
  Zertifikat/Provisioning-Profil als Secrets (z. B. mit fastlane match) benötigt.

## Windows / Linux

`flutter build windows --release` bzw. `flutter build linux --release --dart-define=…`; das Ergebnis liegt unter
`build/<plattform>/…/release`. Für Linux werden `clang`, `cmake`, `ninja-build`, `libgtk-3-dev` benötigt.

## Versionierung

`pubspec.yaml` → `version: MAJOR.MINOR.PATCH+BUILD`. Releases per Git-Tag (`darts-v0.1.0`);
`flutter build … --build-name=0.1.0 --build-number=<CI-Lauf>` überschreibt die Version in CI.

## Betrieb

* **Backups:** Firestore → *Datensicherung/Export* (`gcloud firestore export`) oder geplante Sicherungen.
* **Kosten:** Spark-Tarif reicht für Hosting, Auth und moderate Firestore-Nutzung; Functions benötigen Blaze.
  Pro Aufnahme entstehen 1 Schreibvorgang und je Zuschauer-Gerät 1 Lesevorgang – für Turniere unkritisch.
* **Zuschauer ohne Konto:** *Anonyme Anmeldung* aktivieren und Spielern den Link zur Web-App geben; öffentliche
  Turniere/Spiele (`isPublic`) sind lesbar.
