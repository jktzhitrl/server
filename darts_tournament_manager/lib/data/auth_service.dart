import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../core/auth/permissions.dart';
import '../core/models/ids.dart';
import 'models.dart';
import 'repository.dart';

/// Anmeldung. [LocalAuthService] = Demo ohne Server, [FirebaseAuthService] =
/// echte Konten (E-Mail/Passwort) mit Rollen aus der Collection `users`.
abstract class AuthService {
  Stream<AppUser?> get userStream;
  AppUser? get currentUser;
  bool get supportsPassword;
  Future<AppUser> signIn(String email, String password);
  Future<AppUser> register(String name, String email, String password);

  /// Nur Demo-Modus: sofort mit Name und Rolle starten.
  Future<AppUser> signInDemo(String name, Role role);

  /// Zuschauer ohne Konto (Firebase: anonyme Anmeldung, Rolle `spectator`,
  /// es wird kein Benutzerdokument angelegt).
  Future<AppUser> signInAsSpectator();
  Future<void> signOut();
}

class LocalAuthService implements AuthService {
  final AppRepository repo;
  final StreamController<AppUser?> _c = StreamController<AppUser?>.broadcast();
  AppUser? _user;
  LocalAuthService(this.repo);

  @override
  AppUser? get currentUser => _user;
  @override
  bool get supportsPassword => false;

  @override
  Stream<AppUser?> get userStream async* {
    yield _user;
    yield* _c.stream;
  }

  void _set(AppUser? u) {
    _user = u;
    _c.add(u);
  }

  @override
  Future<AppUser> signInDemo(String name, Role role) async {
    final uid = 'demo-${name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    var u = await repo.getUser(uid);
    u = AppUser(uid: uid, displayName: name.trim(), role: role, playerId: u?.playerId);
    if (u.playerId == null) {
      final p = await repo.savePlayer(PlayerProfile(id: newId('pl'), name: u.displayName, uid: uid));
      u = u.copyWith(playerId: p.id);
    }
    await repo.saveUser(u);
    _set(u);
    return u;
  }

  @override
  Future<AppUser> signInAsSpectator() => signInDemo('Zuschauer', Role.spectator);

  @override
  Future<AppUser> signIn(String email, String password) =>
      throw UnsupportedError('Im Demo-Modus gibt es keine Passwort-Anmeldung');
  @override
  Future<AppUser> register(String name, String email, String password) =>
      throw UnsupportedError('Im Demo-Modus gibt es keine Registrierung');
  @override
  Future<void> signOut() async => _set(null);
}

class FirebaseAuthService implements AuthService {
  final AppRepository repo;
  final fb.FirebaseAuth _auth;
  AppUser? _user;
  late final StreamController<AppUser?> _c = StreamController<AppUser?>.broadcast();
  StreamSubscription<fb.User?>? _sub;

  FirebaseAuthService(this.repo, {fb.FirebaseAuth? auth}) : _auth = auth ?? fb.FirebaseAuth.instance {
    _sub = _auth.authStateChanges().listen((u) async {
      if (u == null) {
        _user = null;
      } else if (u.isAnonymous) {
        _user = AppUser(uid: u.uid, displayName: 'Zuschauer', role: Role.spectator);
      } else {
        _user = await _load(u);
      }
      _c.add(_user);
    });
  }

  void dispose() => _sub?.cancel();

  @override
  AppUser? get currentUser => _user;
  @override
  bool get supportsPassword => true;

  @override
  Stream<AppUser?> get userStream async* {
    yield _user;
    yield* _c.stream;
  }

  Future<AppUser> _load(fb.User u, {String? name}) async {
    var user = await repo.getUser(u.uid);
    if (user == null) {
      // Erstanmeldung: Rolle IMMER 'player' (Security Rules verbieten Selbstvergabe höherer Rollen).
      final display = name ?? u.displayName ?? u.email?.split('@').first ?? 'Spieler';
      final profile = await repo.savePlayer(PlayerProfile(id: newId('pl'), name: display, uid: u.uid));
      user = AppUser(
          uid: u.uid, displayName: display, email: u.email, role: Role.player, playerId: profile.id);
      await repo.saveUser(user);
    }
    return user;
  }

  @override
  Future<AppUser> signIn(String email, String password) async {
    final c = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    _user = await _load(c.user!);
    _c.add(_user);
    return _user!;
  }

  @override
  Future<AppUser> register(String name, String email, String password) async {
    final c = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    await c.user!.updateDisplayName(name.trim());
    _user = await _load(c.user!, name: name.trim());
    _c.add(_user);
    return _user!;
  }

  @override
  Future<AppUser> signInAsSpectator() async {
    final c = await _auth.signInAnonymously();
    _user = AppUser(uid: c.user!.uid, displayName: 'Zuschauer', role: Role.spectator);
    _c.add(_user);
    return _user!;
  }

  @override
  Future<AppUser> signInDemo(String name, Role role) =>
      throw UnsupportedError('Demo-Anmeldung ist nur ohne Firebase möglich');

  @override
  Future<void> signOut() => _auth.signOut();
}
