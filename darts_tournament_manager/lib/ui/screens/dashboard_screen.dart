import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/permissions.dart';
import '../../core/tournament/tournament_plan.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/services.dart';
import '../theme.dart';
import 'live_screen.dart';
import 'new_match_screen.dart';
import 'stats_screens.dart';
import 'tournament_screens.dart';

/// Dashboard + persönliches Spielerportal.
class DashboardScreen extends StatelessWidget {
  final ValueChanged<int> goTo;
  const DashboardScreen({super.key, required this.goTo});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    final user = context.watch<AppUser>();
    return StreamBuilder<List<TournamentRecord>>(
      stream: repo.watchTournaments(),
      builder: (context, ts) => StreamBuilder<List<MatchRecord>>(
        stream: repo.watchMatches(),
        builder: (context, ms) {
          final tournaments = ts.data ?? const <TournamentRecord>[];
          final matches = ms.data ?? const <MatchRecord>[];
          final pid = user.playerId;
          final live = matches.where((m) => m.status == MatchStatus.live || m.status == MatchStatus.paused).toList();
          final mine = pid == null ? const <TournamentRecord>[] : tournaments.where((t) => t.plan?.participants.any((p) => p.id == pid) ?? false).toList();
          final myFinished = pid == null
              ? const <MatchRecord>[]
              : matches.where((m) => m.isFinished && m.players.any((p) => p.id == pid)).toList();

          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('Hallo ${user.displayName}', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (user.role != Role.spectator)
                FilledButton.icon(
                  key: const Key('quickNewMatch'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewMatchScreen())),
                  icon: const Icon(Icons.sports_score),
                  label: const Text('Neues Spiel'),
                ),
              OutlinedButton.icon(
                onPressed: () => showJoinDialog(context),
                icon: const Icon(Icons.qr_code),
                label: const Text('Turnier beitreten'),
              ),
              if (can(user.role, Permission.createTournament))
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const TournamentCreateScreen())),
                  icon: const Icon(Icons.add),
                  label: const Text('Neues Turnier'),
                ),
            ]),
            const SizedBox(height: 20),
            if (pid != null) ...[
              const _SectionTitle('Meine nächsten Spiele'),
              _NextMatches(tournaments: mine, playerId: pid, matches: matches),
              const SizedBox(height: 20),
              const _SectionTitle('Mein Turnierstand'),
              _Standings(tournaments: mine, playerId: pid),
              const SizedBox(height: 20),
              const _SectionTitle('Meine Ergebnisse'),
              if (myFinished.isEmpty)
                const Card(child: ListTile(title: Text('Noch keine Ergebnisse'), leading: Icon(Icons.history)))
              else
                for (final m in myFinished.take(5)) _ResultTile(match: m, playerId: pid),
              const SizedBox(height: 20),
              const _SectionTitle('Meine Statistik'),
              Builder(builder: (context) {
                final s = StatsService.forPlayer(pid, matches);
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  StatTile('3-Dart-Average', fmt(s.threeDartAverage, digits: 2)),
                  StatTile('180er', '${s.count180}'),
                  StatTile('Höchstes Checkout', s.highestCheckout?.toString() ?? 'n/v'),
                  StatTile('Checkout-Quote',
                      s.checkoutRate == null ? 'n/v' : '${(s.checkoutRate! * 100).toStringAsFixed(0)} %'),
                  StatTile('Siege / Niederlagen', '${s.matchesWon} / ${s.matchesLost}'),
                ]);
              }),
              const SizedBox(height: 20),
              const _SectionTitle('Meine Turniere'),
              if (mine.isEmpty)
                const Card(child: ListTile(title: Text('Du nimmst an keinem Turnier teil'), leading: Icon(Icons.emoji_events_outlined)))
              else
                for (final t in mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: Icon(t.status == TournamentStatus.finished ? Icons.history : Icons.emoji_events, color: AppColors.accent),
                        title: Text(t.name),
                        subtitle: Text('${t.format.label} · ${statusLabel(t.status)}'),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TournamentDetailScreen(id: t.id))),
                      ),
                    ),
                  ),
              const SizedBox(height: 20),
            ],
            const _SectionTitle('Live jetzt'),
            if (live.isEmpty)
              const Card(child: ListTile(title: Text('Aktuell läuft kein Spiel'), leading: Icon(Icons.sports_bar)))
            else
              for (final m in live.take(4)) MatchTile(match: m),
          ]);
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium));
}

class _NextMatches extends StatelessWidget {
  final List<TournamentRecord> tournaments;
  final String playerId;
  final List<MatchRecord> matches;
  const _NextMatches({required this.tournaments, required this.playerId, required this.matches});
  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final t in tournaments) {
      final plan = t.plan;
      if (plan == null || !t.published || plan.isComplete) continue;
      final next = plan.nextMatchFor(playerId);
      if (next == null) {
        items.add(Card(
          child: ListTile(
            leading: const Icon(Icons.hourglass_empty),
            title: Text(t.name),
            subtitle: Text(plan.bracket?.isEliminated(playerId) ?? false
                ? 'Ausgeschieden'
                : 'Warte auf den nächsten Gegner'),
          ),
        ));
        continue;
      }
      final opp = next.playerIds.firstWhere((id) => id != playerId);
      final running = matches.where((m) => m.planMatchId == next.id && m.status != MatchStatus.confirmed).firstOrNull;
      items.add(Card(
        child: ListTile(
          key: Key('next-${next.id}'),
          leading: Icon(running != null ? Icons.fiber_manual_record : Icons.schedule,
              color: running != null ? AppColors.danger : AppColors.accent),
          title: Text('${t.name}: gegen ${plan.names[opp]}'),
          subtitle: Text(running == null
              ? next.label
              : 'läuft gerade${running.boardId != null ? ' · ${t.boards.where((b) => b.id == running.boardId).map((b) => b.name).firstOrNull ?? ''}' : ''}'),
          trailing: running != null ? const Icon(Icons.chevron_right) : null,
          onTap: running == null
              ? null
              : () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveMatchScreen(matchId: running.id))),
        ),
      ));
    }
    if (items.isEmpty) {
      return const Card(child: ListTile(leading: Icon(Icons.event_available), title: Text('Keine anstehenden Spiele')));
    }
    return Column(children: [for (final w in items) Padding(padding: const EdgeInsets.only(bottom: 8), child: w)]);
  }
}

class _Standings extends StatelessWidget {
  final List<TournamentRecord> tournaments;
  final String playerId;
  const _Standings({required this.tournaments, required this.playerId});
  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    for (final t in tournaments) {
      final plan = t.plan;
      if (plan == null || !t.published) continue;
      String text;
      final tables = plan.tables();
      if (tables.isNotEmpty) {
        final tbl = tables.firstWhere((tb) => tb.any((r) => r.playerId == playerId), orElse: () => const []);
        final row = tbl.where((r) => r.playerId == playerId).firstOrNull;
        text = row == null
            ? 'Platz –'
            : 'Platz ${row.rank} von ${tbl.length} · ${row.points} Pkt · ${row.wins}S/${row.losses}N';
        if (plan.format == TournamentFormat.groupsKnockout && plan.phase == PlanPhase.knockout) {
          text += (plan.bracket?.isEliminated(playerId) ?? false) ? ' · K.-o.: ausgeschieden' : ' · im K.-o.';
        }
      } else if (plan.bracket != null) {
        text = plan.championId == playerId
            ? '🏆 Turniersieger'
            : (plan.bracket!.isEliminated(playerId) ? 'Ausgeschieden' : 'Im Turnier');
      } else {
        continue;
      }
      lines.add(Card(
          child: ListTile(
        leading: const Icon(Icons.leaderboard, color: AppColors.accent),
        title: Text(t.name),
        subtitle: Text(text),
      )));
    }
    if (lines.isEmpty) {
      return const Card(child: ListTile(leading: Icon(Icons.leaderboard), title: Text('Noch kein Turnierstand')));
    }
    return Column(children: [for (final w in lines) Padding(padding: const EdgeInsets.only(bottom: 8), child: w)]);
  }
}

class _ResultTile extends StatelessWidget {
  final MatchRecord match;
  final String playerId;
  const _ResultTile({required this.match, required this.playerId});
  @override
  Widget build(BuildContext context) {
    final won = match.winnerId == playerId;
    final opp = match.players.where((p) => p.id != playerId).map((p) => p.name).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: Icon(won ? Icons.check_circle : Icons.cancel, color: won ? AppColors.accent : AppColors.danger),
          title: Text('${won ? 'Sieg' : 'Niederlage'} gegen ${opp.isEmpty ? '–' : opp}'),
          subtitle: Text(matchSummaryLine(match)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveMatchScreen(matchId: match.id))),
        ),
      ),
    );
  }
}
