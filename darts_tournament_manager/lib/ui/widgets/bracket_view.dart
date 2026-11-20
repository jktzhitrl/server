import 'package:flutter/material.dart';

import '../../core/tournament/bracket.dart';
import '../theme.dart';

/// Turnierbaum: Runden als Spalten, horizontal scrollbar. Bei Double Elimination
/// werden Gewinner-, Verliererbaum und Grand Final untereinander gezeigt.
class BracketView extends StatelessWidget {
  final Bracket bracket;
  final Map<String, String> names;
  final void Function(BracketMatch match)? onTapMatch;
  final String? highlightPlayerId;
  final Set<String> runningMatchIds;
  const BracketView({
    super.key,
    required this.bracket,
    required this.names,
    this.onTapMatch,
    this.highlightPlayerId,
    this.runningMatchIds = const {},
  });

  @override
  Widget build(BuildContext context) {
    final sides = [
      ('W', bracket.type == BracketType.double ? 'Gewinnerbaum' : 'Turnierbaum'),
      if (bracket.type == BracketType.double) ('L', 'Verliererbaum'),
      if (bracket.type == BracketType.double) ('G', 'Grand Final'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (bracket.championId != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            color: AppColors.accentDim,
            child: ListTile(
              leading: const Icon(Icons.emoji_events, color: AppColors.warning),
              title: Text('Turniersieger: ${names[bracket.championId] ?? bracket.championId}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
          ),
        ),
      for (final (side, title) in sides) ...[
        if (bracket.matches.any((m) => m.side == side && !m.dead)) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var r = 1; r <= bracket.roundsOf(side); r++)
                _RoundColumn(
                  label: bracket.roundLabel(side, r),
                  matches: bracket.roundMatches(side, r).where((m) => !m.dead).toList(),
                  names: names,
                  onTap: onTapMatch,
                  highlight: highlightPlayerId,
                  running: runningMatchIds,
                ),
            ]),
          ),
        ],
      ],
    ]);
  }
}

class _RoundColumn extends StatelessWidget {
  final String label;
  final List<BracketMatch> matches;
  final Map<String, String> names;
  final void Function(BracketMatch)? onTap;
  final String? highlight;
  final Set<String> running;
  const _RoundColumn({
    required this.label,
    required this.matches,
    required this.names,
    required this.onTap,
    required this.highlight,
    required this.running,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: SizedBox(
        width: 210,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final m in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MatchBox(
                  match: m, names: names, onTap: onTap, highlight: highlight, running: running.contains(m.id)),
            ),
        ]),
      ),
    );
  }
}

class _MatchBox extends StatelessWidget {
  final BracketMatch match;
  final Map<String, String> names;
  final void Function(BracketMatch)? onTap;
  final String? highlight;
  final bool running;
  const _MatchBox(
      {required this.match, required this.names, required this.onTap, required this.highlight, required this.running});

  Widget _row(Slot slot, int? score, bool isWinner) {
    String text;
    if (slot.playerId != null) {
      text = names[slot.playerId] ?? slot.playerId!;
    } else if (slot.dead) {
      text = 'Freilos';
    } else {
      text = 'offen';
    }
    final dim = slot.playerId == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: isWinner ? FontWeight.w800 : FontWeight.w500,
                  color: dim
                      ? AppColors.textDim
                      : (slot.playerId == highlight ? AppColors.accent : null),
                  fontStyle: dim ? FontStyle.italic : null)),
        ),
        if (score != null) Text('$score', style: const TextStyle(fontWeight: FontWeight.w800)),
        if (isWinner) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.check, size: 16, color: AppColors.accent)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playable = match.isPlayable;
    return InkWell(
      key: Key('bracket-${match.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap == null ? null : () => onTap!(match),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: running
                  ? AppColors.danger
                  : playable
                      ? AppColors.accent
                      : const Color(0xFF22302A),
              width: playable || running ? 2 : 1),
        ),
        child: Column(children: [
          _row(match.a, match.scoreA, match.winnerId != null && match.winnerId == match.a.playerId),
          const Divider(height: 1),
          _row(match.b, match.scoreB, match.winnerId != null && match.winnerId == match.b.playerId),
        ]),
      ),
    );
  }
}
