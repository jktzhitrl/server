import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../bootstrap.dart';
import '../../core/auth/permissions.dart';
import '../../data/auth_service.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../theme.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    final repo = context.read<AppRepository>();
    final auth = context.read<AuthService>();
    final services = context.read<AppServices>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Einstellungen', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.person),
          title: Text(user.displayName),
          subtitle: Text('${roleLabel(user.role)}${user.email != null ? ' · ${user.email}' : ''}'),
          trailing: TextButton(
            key: const Key('signOut'),
            onPressed: () => auth.signOut(),
            child: const Text('Abmelden'),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          leading: Icon(services.isRemote ? Icons.cloud_done : Icons.cloud_off,
              color: services.isRemote ? AppColors.accent : AppColors.warning),
          title: Text(services.isRemote ? 'Firebase verbunden' : 'Demo-Modus (lokal)'),
          subtitle: Text(services.isRemote
              ? 'Spielstände werden in Echtzeit zwischen allen Geräten synchronisiert.'
              : 'Daten liegen nur auf diesem Gerät. Zum Teilen Firebase konfigurieren (docs/FIREBASE_SETUP.md).'),
        ),
      ),
      const SizedBox(height: 8),
      if (user.playerId != null)
        StreamBuilder<List<PlayerProfile>>(
          stream: repo.watchPlayers(),
          builder: (context, snap) {
            final me = snap.data?.where((p) => p.id == user.playerId).firstOrNull;
            if (me == null) return const SizedBox.shrink();
            return Card(
              child: ListTile(
                leading: const Icon(Icons.adjust),
                title: const Text('Lieblingsdoppel'),
                subtitle: const Text('Wird bei den Checkout-Vorschlägen berücksichtigt.'),
                trailing: DropdownButton<int?>(
                  key: const Key('favoriteDouble'),
                  value: me.favoriteDouble,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('–')),
                    for (var i = 1; i <= 20; i++) DropdownMenuItem(value: i, child: Text('D$i')),
                    const DropdownMenuItem(value: 25, child: Text('Bull')),
                  ],
                  onChanged: (v) => repo.savePlayer(v == null
                      ? me.copyWith(clearFavorite: true)
                      : me.copyWith(favoriteDouble: v)),
                ),
              ),
            );
          },
        ),
      if (!services.isRemote) ...[
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.admin_panel_settings),
            title: const Text('Rolle wechseln (nur Demo)'),
            trailing: DropdownButton<Role>(
              key: const Key('demoRole'),
              value: user.role,
              items: [for (final r in Role.values.reversed) DropdownMenuItem(value: r, child: Text(roleLabel(r)))],
              onChanged: (r) async {
                if (r != null) await auth.signInDemo(user.displayName, r);
              },
            ),
          ),
        ),
      ],
      if (can(user.role, Permission.manageRoles)) ...[
        const SizedBox(height: 16),
        Text('Benutzer & Rollen', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        StreamBuilder<List<AppUser>>(
          stream: repo.watchUsers(),
          builder: (context, snap) => Column(children: [
            for (final u in snap.data ?? const <AppUser>[])
              Card(
                child: ListTile(
                  title: Text(u.displayName),
                  subtitle: Text(u.email ?? u.uid),
                  trailing: DropdownButton<Role>(
                    value: u.role,
                    items: [for (final r in Role.values.reversed) DropdownMenuItem(value: r, child: Text(roleLabel(r)))],
                    onChanged: u.uid == user.uid ? null : (r) => r == null ? null : repo.saveUser(u.copyWith(role: r)),
                  ),
                ),
              ),
          ]),
        ),
      ],
      if (can(user.role, Permission.viewAuditLog)) ...[
        const SizedBox(height: 16),
        Text('Protokoll (Audit-Log)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        StreamBuilder<List<AuditEntry>>(
          stream: repo.watchAudit(),
          builder: (context, snap) {
            final list = (snap.data ?? const <AuditEntry>[]).take(30).toList();
            if (list.isEmpty) return const Text('Keine Einträge.', style: TextStyle(color: AppColors.textDim));
            return Card(
              child: Column(children: [
                for (final e in list)
                  ListTile(
                    dense: true,
                    title: Text(e.action),
                    subtitle: Text('${e.at.toLocal().toString().substring(0, 19)} · ${e.uid}${e.detail.isEmpty ? '' : ' · ${e.detail}'}'),
                  ),
              ]),
            );
          },
        ),
      ],
      const SizedBox(height: 24),
      const Text('Darts Tournament Manager Pro · Version 0.1.0',
          textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
    ]);
  }
}
