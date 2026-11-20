import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'bootstrap.dart';
import 'data/auth_service.dart';
import 'data/models.dart';
import 'data/repository.dart';
import 'data/services.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/login_screen.dart';
import 'ui/theme.dart';

class DartsApp extends StatelessWidget {
  final AppServices services;
  const DartsApp({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        Provider<AppRepository>.value(value: services.repo),
        Provider<AuthService>.value(value: services.auth),
        Provider<TournamentService>.value(value: services.tournaments),
      ],
      child: MaterialApp(
        title: 'Darts Tournament Manager Pro',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Der angemeldete Benutzer wird oberhalb des Navigators bereitgestellt,
        // damit auch per Navigator.push geöffnete Seiten ihn lesen können.
        builder: (context, child) => StreamBuilder<AppUser?>(
          stream: services.auth.userStream,
          initialData: services.auth.currentUser,
          builder: (context, snap) {
            final user = snap.data;
            return user == null
                ? child!
                : Provider<AppUser>.value(value: user, child: child!);
          },
        ),
        home: const AuthGate(),
      ),
    );
  }
}

/// Zeigt Anmeldung oder Hauptoberfläche je nach Anmeldestatus.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder<AppUser?>(
      stream: auth.userStream,
      initialData: auth.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return const HomeShell();
      },
    );
  }
}
