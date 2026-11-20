import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/rules.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../theme.dart';
import '../widgets/scoreboard.dart';
import 'scoring_screen.dart';

/// Liste aller laufenden Spiele (Echtzeit).
class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    return StreamBuilder<List<MatchRecord>>(
      stream: repo.watchMatches(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        final live = all.where((m) => m.status != MatchStatus.confirmed).toList();
        final done = all.where((m) => m.status == MatchStatus.confirmed).take(10).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Live-Spiele', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          if (live.isEmpty)
            const Card(child: ListTile(title: Text('Aktuell läuft kein Spiel.'), leading: Icon(Icons.sports_bar))),
          for (final m in live) MatchTile(match: m),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Zuletzt beendet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final m in done) MatchTile(match: m),
          ],
        ]);
      },
    );
  }
}

String matchSummaryLine(MatchRecord m) {
  final x = m.x01;
  if (x != null) {
    final s = x.state;
    final score = [
      for (var i = 0; i < m.players.length; i++)
        x.rules.format.usesSets ? '${s.setsWon[i]}(${s.legsWon[i]})' : '${s.totalLegsWon[i]}'
    ].join(' : ');
    return '${m.gameType.label} · $score';
  }
  return m.gameType.label;
}

class MatchTile extends StatelessWidget {
  final MatchRecord match;
  const MatchTile({super.key, required this.match});
  @override
  Widget build(BuildContext context) {
    final m = match;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: Icon(
              m.status == MatchStatus.live
                  ? Icons.fiber_manual_record
                  : m.status == MatchStatus.paused
                      ? Icons.pause_circle
                      : Icons.check_circle,
              color: m.status == MatchStatus.live ? AppColors.danger : AppColors.textDim),
          title: Text(m.players.map((p) => p.name).join('  –  ')),
          subtitle: Text(matchSummaryLine(m)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => LiveMatchScreen(matchId: m.id))),
        ),
      ),
    );
  }
}

/// Zuschauer-/TV-Ansicht eines Spiels mit automatischer Aktualisierung.
class LiveMatchScreen extends StatefulWidget {
  final String matchId;
  final bool tv;
  const LiveMatchScreen({super.key, required this.matchId, this.tv = false});
  @override
  State<LiveMatchScreen> createState() => _LiveMatchScreenState();
}

class _LiveMatchScreenState extends State<LiveMatchScreen> {
  late bool _tv = widget.tv;

  @override
  void initState() {
    super.initState();
    if (_tv) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleTv() {
    setState(() => _tv = !_tv);
    SystemChrome.setEnabledSystemUIMode(_tv ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    return StreamBuilder<MatchRecord?>(
      stream: repo.watchMatch(widget.matchId),
      builder: (context, snap) {
        final m = snap.data;
        return Scaffold(
          appBar: _tv
              ? null
              : AppBar(title: Text(m == null ? 'Spiel' : m.players.map((p) => p.name).join(' – ')), actions: [
                  IconButton(tooltip: 'Vollbild / TV-Modus', icon: const Icon(Icons.fullscreen), onPressed: _toggleTv),
                  IconButton(
                    tooltip: 'Eingabe',
                    icon: const Icon(Icons.edit_note),
                    onPressed: m == null
                        ? null
                        : () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ScoringScreen(matchId: m.id))),
                  ),
                ]),
          body: SafeArea(
            child: !snap.hasData
                ? const Center(child: CircularProgressIndicator())
                : m == null
                    ? const Center(child: Text('Begegnung nicht gefunden'))
                    : Stack(children: [
                        SingleChildScrollView(
                          padding: EdgeInsets.all(_tv ? 32 : 16),
                          child: ScoreboardView(match: m, tv: _tv),
                        ),
                        if (_tv)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: IconButton(
                                tooltip: 'TV-Modus beenden',
                                icon: const Icon(Icons.fullscreen_exit),
                                onPressed: _toggleTv),
                          ),
                      ]),
          ),
        );
      },
    );
  }
}
