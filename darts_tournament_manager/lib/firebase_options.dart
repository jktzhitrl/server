import 'package:firebase_core/firebase_core.dart';

/// Firebase-Konfiguration aus `--dart-define` (keine Zugangsdaten im Repository).
///
/// Beispiel:
/// ```
/// flutter run -d chrome \
///   --dart-define=FIREBASE_API_KEY=... \
///   --dart-define=FIREBASE_APP_ID=... \
///   --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
///   --dart-define=FIREBASE_PROJECT_ID=... \
///   --dart-define=FIREBASE_AUTH_DOMAIN=... \
///   --dart-define=FIREBASE_STORAGE_BUCKET=...
/// ```
/// Ohne `FIREBASE_PROJECT_ID` startet die App im Demo-Modus (lokale Daten).
/// Siehe docs/FIREBASE_SETUP.md. (Die Web-API-Keys von Firebase sind keine
/// Geheimnisse, der Schutz erfolgt über Security Rules - sie gehören dennoch
/// nicht in das Repository, sondern in GitHub-Secrets.)
class AppFirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static bool get isConfigured => projectId.isNotEmpty && apiKey.isNotEmpty && appId.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        authDomain: authDomain.isEmpty ? null : authDomain,
        storageBucket: storageBucket.isEmpty ? null : storageBucket,
      );
}
