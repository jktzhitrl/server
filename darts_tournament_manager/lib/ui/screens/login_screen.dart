import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../bootstrap.dart';
import '../../core/auth/permissions.dart';
import '../../data/auth_service.dart';
import '../theme.dart';

String roleLabel(Role r) => switch (r) {
      Role.admin => 'Administrator',
      Role.director => 'Turnierleitung',
      Role.scorer => 'Schreiber / Caller',
      Role.player => 'Spieler',
      Role.spectator => 'Zuschauer',
    };

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;
  Role _demoRole = Role.admin;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final services = context.read<AppServices>();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.track_changes, size: 72, color: AppColors.accent),
                const SizedBox(height: 12),
                Text('Darts Tournament Manager Pro',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  services.isRemote ? 'Live-Synchronisierung über Firebase' : 'Demo-Modus (lokale Daten, ohne Server)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textDim),
                ),
                if (services.firebaseError != null) ...[
                  const SizedBox(height: 8),
                  Text(services.firebaseError!, style: const TextStyle(color: AppColors.warning)),
                ],
                const SizedBox(height: 28),
                if (auth.supportsPassword) ...[
                  if (_register)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Anzeigename')),
                    ),
                  TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'E-Mail')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Passwort')),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              if (_register) {
                                await auth.register(_name.text, _email.text, _password.text);
                              } else {
                                await auth.signIn(_email.text, _password.text);
                              }
                            }),
                    child: Text(_register ? 'Konto erstellen' : 'Anmelden'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _register = !_register),
                    child: Text(_register ? 'Ich habe schon ein Konto' : 'Neues Konto erstellen'),
                  ),
                ] else ...[
                  TextField(
                      key: const Key('demoName'),
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Dein Name')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Role>(
                    value: _demoRole,
                    decoration: const InputDecoration(labelText: 'Rolle (Demo)'),
                    items: [
                      for (final r in Role.values.reversed)
                        DropdownMenuItem(value: r, child: Text(roleLabel(r))),
                    ],
                    onChanged: (r) => setState(() => _demoRole = r ?? Role.admin),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('demoStart'),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              if (_name.text.trim().isEmpty) throw 'Bitte einen Namen eingeben.';
                              await auth.signInDemo(_name.text, _demoRole);
                            }),
                    child: const Text('Starten'),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('spectatorStart'),
                  onPressed: _busy ? null : () => _run(() async {
                        await auth.signInAsSpectator();
                      }),
                  icon: const Icon(Icons.visibility),
                  label: const Text('Als Zuschauer ansehen'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
