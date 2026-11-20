import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'live_screen.dart';
import 'settings_screen.dart';
import 'stats_screens.dart';
import 'tournament_screens.dart';

/// Responsive Navigation: Rail auf Tablet/Desktop, Bottom-Bar auf dem Smartphone.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  static bool _inviteHandled = false;

  static const _items = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    (Icons.emoji_events_outlined, Icons.emoji_events, 'Turniere'),
    (Icons.sports_bar_outlined, Icons.sports_bar, 'Live'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Statistiken'),
    (Icons.settings_outlined, Icons.settings, 'Einstellungen'),
  ];

  @override
  void initState() {
    super.initState();
    // Einladungslink (?join=CODE) öffnet den Beitritts-Dialog.
    if (kIsWeb && !_inviteHandled) {
      final code = Uri.base.queryParameters['join'];
      if (code != null && code.isNotEmpty) {
        _inviteHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showJoinDialog(context, code: code);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(goTo: (i) => setState(() => _index = i)),
      const TournamentListScreen(),
      const LiveScreen(),
      const StatsScreen(),
      const SettingsScreen(),
    ];
    final body = IndexedStack(index: _index, children: pages);
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 800;
      if (wide) {
        return Scaffold(
          body: SafeArea(
            child: Row(children: [
              NavigationRail(
                selectedIndex: _index,
                extended: c.maxWidth >= 1100,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final it in _items)
                    NavigationRailDestination(
                        icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: Text(it.$3)),
                ],
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1200), child: body),
                ),
              ),
            ]),
          ),
        );
      }
      return Scaffold(
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final it in _items)
              NavigationDestination(icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: it.$3),
          ],
        ),
      );
    });
  }
}
