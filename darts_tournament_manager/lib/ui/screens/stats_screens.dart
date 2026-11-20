import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/rules.dart';
import '../../core/stats/player_stats.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/services.dart';
import '../theme.dart';
import '../widgets/scoreboard.dart';

String fmt(double? v, {int digits = 1, String suffix = ''}) =>
    v == null ? 'n/v' : '${v.toStringAsFixed(digits)}$suffix';

/// Kachel für eine Kennzahl; "n/v" = nicht verfügbar (fehlende Daten).
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  const StatTile(this.label, this.value, {super.key, this.hint});
  @override
  Widget build(BuildContext context) {
    final unavailable = value == 'n/v';
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF22302A))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: bigNumber.copyWith(
                fontSize: 26, color: unavailable ? AppColors.textDim : AppColors.accent)),
        if (hint != null) Text(hint!, style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
      ]),
    );
  }
}

/// Alle Kennzahlen eines Spielers.
class StatsGrid extends StatelessWidget {
  final PlayerStats s;
  const StatsGrid(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final unknownCo = s.checkoutsWithUnknownAttempts;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        StatTile('3-Dart-Average', fmt(s.threeDartAverage, digits: 2)),
        StatTile('First-9-Average', fmt(s.first9Average, digits: 2)),
        StatTile('Siege / Niederlagen', '${s.matchesWon} / ${s.matchesLost}'),
        StatTile('Legs gespielt', '${s.legsPlayed}'),
        StatTile('Legs gewonnen', '${s.legsWon}'),
        StatTile('Legs verloren', '${s.legsLost}'),
        StatTile('Sätze gewonnen', '${s.setsWon}'),
        StatTile('180er', '${s.count180}'),
        StatTile('140+', '${s.count140Plus}'),
        StatTile('100+', '${s.count100Plus}'),
        StatTile('Höchste Aufnahme', s.visitCount == 0 ? 'n/v' : '${s.highestVisit}'),
        StatTile('Höchstes Checkout', s.highestCheckout?.toString() ?? 'n/v'),
        StatTile('Ø Checkout', fmt(s.averageCheckout)),
        StatTile('Checkout-Quote',
            s.checkoutRate == null ? 'n/v' : '${(s.checkoutRate! * 100).toStringAsFixed(1)} %',
            hint: s.checkoutRate == null
                ? 'keine Versuche erfasst'
                : '${s.checkoutHits}/${s.checkoutAttempts}${unknownCo > 0 ? ' · $unknownCo ohne Angabe' : ''}'),
        StatTile('Geworfene Darts', '${s.dartsThrown}'),
        StatTile('Gesamtpunkte', '${s.totalScore}'),
        StatTile('Bestes Leg', s.bestLegDarts == null ? 'n/v' : '${s.bestLegDarts} Darts'),
        StatTile('Schlechtestes Leg', s.worstLegDarts == null ? 'n/v' : '${s.worstLegDarts} Darts'),
      ]),
      const SizedBox(height: 20),
      Text('Doppelquote je Feld', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (s.doubleStats == null || s.doubleStats!.isEmpty)
        const Text(
            'Nicht verfügbar – dafür sind Einzeldart-Daten (Eingabe pro Wurf) nötig.',
            style: TextStyle(color: AppColors.textDim))
      else
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              for (final k in s.preferredDoubles!)
                ListTile(
                  dense: true,
                  leading: Text(k == 25 ? 'Bull' : 'D$k',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  title: LinearProgressIndicator(value: s.doubleStats![k]!.rate, minHeight: 8),
                  trailing: Text(
                      '${(s.doubleStats![k]!.rate * 100).toStringAsFixed(0)} %  (${s.doubleStats![k]!.hits}/${s.doubleStats![k]!.attempts})'),
                ),
            ]),
          ),
        ),
    ]);
  }
}

/// Statistik-Bereich: Spieler-Statistik, Rangliste, Spielerprofile.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: Column(children: [
        TabBar(tabs: [
          Tab(text: 'Meine Statistik'),
          Tab(text: 'Rangliste'),
          Tab(text: 'Spielerprofile'),
        ]),
        Expanded(
          child: TabBarView(children: [
            PlayerStatsView(),
            LeaderboardView(),
            PlayersView(),
          ]),
        ),
      ]),
    );
  }
}

enum _Scope { career, tournament, match }

class PlayerStatsView extends StatefulWidget {
  final String? playerId;
  const PlayerStatsView({super.key, this.playerId});
  @override
  State<PlayerStatsView> createState() => _PlayerStatsViewState();
}

class _PlayerStatsViewState extends State<PlayerStatsView> {
  String? _player;
  _Scope _scope = _Scope.career;
  String? _tournamentId;
  String? _matchId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    final me = context.watch<AppUser>();
    final pid = _player ?? widget.playerId ?? me.playerId;
    return StreamBuilder<List<PlayerProfile>>(
      stream: repo.watchPlayers(),
      builder: (context, ps) => StreamBuilder<List<MatchRecord>>(
        stream: repo.watchMatches(),
        builder: (context, ms) => StreamBuilder<List<TournamentRecord>>(
          stream: repo.watchTournaments(),
          builder: (context, ts) {
            if (!ps.hasData || !ms.hasData || !ts.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final players = ps.data!;
            final selected = players.where((p) => p.id == pid).firstOrNull;
            final all = ms.data!.where((m) => m.players.any((p) => p.id == pid) && m.gameType.isX01 && m.isFinished).toList();
            var used = all;
            if (_scope == _Scope.tournament && _tournamentId != null) {
              used = all.where((m) => m.tournamentId == _tournamentId).toList();
            }
            if (_scope == _Scope.match && _matchId != null) {
              used = all.where((m) => m.id == _matchId).toList();
            }
            final stats = pid == null ? null : StatsService.forPlayer(pid, used);
            final myTournaments = ts.data!
                .where((t) => all.any((m) => m.tournamentId == t.id))
                .toList();
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (widget.playerId == null)
                DropdownButtonFormField<String>(
                  value: players.any((p) => p.id == pid) ? pid : null,
                  decoration: const InputDecoration(labelText: 'Spieler'),
                  items: [for (final p in players) DropdownMenuItem(value: p.id, child: Text(p.name))],
                  onChanged: (v) => setState(() {
                    _player = v;
                    _matchId = null;
                    _tournamentId = null;
                  }),
                ),
              const SizedBox(height: 12),
              SegmentedButton<_Scope>(
                segments: const [
                  ButtonSegment(value: _Scope.career, label: Text('Karriere')),
                  ButtonSegment(value: _Scope.tournament, label: Text('Turnier')),
                  ButtonSegment(value: _Scope.match, label: Text('Spiel')),
                ],
                selected: {_scope},
                onSelectionChanged: (s) => setState(() => _scope = s.first),
              ),
              if (_scope == _Scope.tournament)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: DropdownButtonFormField<String>(
                    value: myTournaments.any((t) => t.id == _tournamentId) ? _tournamentId : null,
                    decoration: const InputDecoration(labelText: 'Turnier'),
                    items: [for (final t in myTournaments) DropdownMenuItem(value: t.id, child: Text(t.name))],
                    onChanged: (v) => setState(() => _tournamentId = v),
                  ),
                ),
              if (_scope == _Scope.match)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: DropdownButtonFormField<String>(
                    value: all.any((m) => m.id == _matchId) ? _matchId : null,
                    decoration: const InputDecoration(labelText: 'Spiel'),
                    items: [
                      for (final m in all)
                        DropdownMenuItem(
                            value: m.id,
                            child: Text('${m.players.map((p) => p.name).join(' – ')} (${m.updatedAt.toLocal().toString().substring(0, 16)})')),
                    ],
                    onChanged: (v) => setState(() => _matchId = v),
                  ),
                ),
              const SizedBox(height: 16),
              if (selected != null)
                Row(children: [
                  PlayerAvatar(selected.name, radius: 24),
                  const SizedBox(width: 12),
                  Text(selected.name, style: Theme.of(context).textTheme.headlineSmall),
                ]),
              const SizedBox(height: 12),
              if (stats == null || (stats.legsPlayed == 0 && stats.matchesWon + stats.matchesLost == 0))
                const Card(
                    child: ListTile(
                        leading: Icon(Icons.query_stats),
                        title: Text('Noch keine beendeten Spiele'),
                        subtitle: Text('Sobald Spiele abgeschlossen sind, erscheinen hier die Statistiken.')))
              else
                StatsGrid(stats),
            ]);
          },
        ),
      ),
    );
  }
}

/// Rangliste aller Spieler nach 3-Dart-Average (mind. 1 beendetes Spiel).
class LeaderboardView extends StatelessWidget {
  const LeaderboardView({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    return StreamBuilder<List<PlayerProfile>>(
      stream: repo.watchPlayers(),
      builder: (context, ps) => StreamBuilder<List<MatchRecord>>(
        stream: repo.watchMatches(),
        builder: (context, ms) {
          if (!ps.hasData || !ms.hasData) return const Center(child: CircularProgressIndicator());
          final rows = <(PlayerProfile, dynamic)>[
            for (final p in ps.data!) (p, StatsService.forPlayer(p.id, ms.data!)),
          ].where((r) => r.$2.legsPlayed > 0).toList()
            ..sort((a, b) => (b.$2.threeDartAverage ?? 0).compareTo(a.$2.threeDartAverage ?? 0));
          if (rows.isEmpty) {
            return const Center(child: Text('Noch keine Ergebnisse.', style: TextStyle(color: AppColors.textDim)));
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Spieler')),
                  DataColumn(label: Text('Ø'), numeric: true),
                  DataColumn(label: Text('S/N'), numeric: true),
                  DataColumn(label: Text('180'), numeric: true),
                  DataColumn(label: Text('Max CO'), numeric: true),
                ], rows: [
                  for (var i = 0; i < rows.length; i++)
                    DataRow(cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(rows[i].$1.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text(fmt(rows[i].$2.threeDartAverage, digits: 2))),
                      DataCell(Text('${rows[i].$2.matchesWon}/${rows[i].$2.matchesLost}')),
                      DataCell(Text('${rows[i].$2.count180}')),
                      DataCell(Text('${rows[i].$2.highestCheckout ?? '–'}')),
                    ]),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Spielerprofile (Liste, Lieblingsdoppel, Detailstatistik).
class PlayersView extends StatelessWidget {
  const PlayersView({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    return StreamBuilder<List<PlayerProfile>>(
      stream: repo.watchPlayers(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final players = snap.data!;
        if (players.isEmpty) {
          return const Center(child: Text('Noch keine Spieler.', style: TextStyle(color: AppColors.textDim)));
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final p in players)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: PlayerAvatar(p.name),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(p.favoriteDouble == null
                      ? 'Lieblingsdoppel: –'
                      : 'Lieblingsdoppel: ${p.favoriteDouble == 25 ? 'Bull' : 'D${p.favoriteDouble}'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(player: p))),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

class PlayerProfileScreen extends StatelessWidget {
  final PlayerProfile player;
  const PlayerProfileScreen({super.key, required this.player});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(player.name)),
      body: PlayerStatsView(playerId: player.id),
    );
  }
}
