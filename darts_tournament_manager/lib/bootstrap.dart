import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/auth_service.dart';
import 'data/firestore_repository.dart';
import 'data/local_repository.dart';
import 'data/repository.dart';
import 'data/services.dart';
import 'firebase_options.dart';

/// Alle Dienste der App.
class AppServices {
  final AppRepository repo;
  final AuthService auth;
  final TournamentService tournaments;

  /// Fehlermeldung, falls Firebase konfiguriert war, aber nicht startete.
  final String? firebaseError;

  AppServices({required this.repo, required this.auth, this.firebaseError})
      : tournaments = TournamentService(repo);

  bool get isRemote => repo.isRemote;
}

const _prefsKey = 'dtm_local_db_v1';

/// Startet Firebase, falls konfiguriert (siehe `firebase_options.dart`),
/// sonst den Demo-Modus mit lokaler Speicherung.
Future<AppServices> bootstrap() async {
  String? error;
  if (AppFirebaseConfig.isConfigured) {
    try {
      await Firebase.initializeApp(options: AppFirebaseConfig.options);
      try {
        // Lokaler Cache: Lesen funktioniert auch bei Verbindungsabbruch, Streams
        // verbinden sich danach automatisch neu (Web: Persistenz nur Einzel-Tab).
        FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
      } catch (_) {}
      final repo = FirestoreRepository();
      return AppServices(repo: repo, auth: FirebaseAuthService(repo));
    } catch (e) {
      error = 'Firebase konnte nicht gestartet werden: $e';
    }
  }
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {}
  final repo = LocalRepository(
    initialJson: prefs?.getString(_prefsKey),
    persist: prefs == null ? null : (json) async {
      await prefs!.setString(_prefsKey, json);
    },
  );
  return AppServices(repo: repo, auth: LocalAuthService(repo), firebaseError: error);
}
