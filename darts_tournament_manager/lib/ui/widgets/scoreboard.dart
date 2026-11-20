import 'package:flutter/material.dart';

import '../../core/checkout/checkout_calculator.dart';
import '../../core/games/around_the_clock.dart';
import '../../core/games/cricket.dart';
import '../../core/models/dart_throw.dart';
import '../../core/models/rules.dart';
import '../../data/models.dart';
import '../theme.dart';

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}

class PlayerAvatar extends StatelessWidget {
  final String name;
  final double radius;
  const PlayerAvatar(this.name, {super.key, this.radius = 20});
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.accentDim,
        child: Text(initials(name),
            style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w700, color: Colors.white)),
      );
}

/// Kompakte Checkout-Vorschläge für den aktiven Spieler.
class CheckoutPanel extends StatelessWidget {
  final int remaining;
  final OutMode outMode;
  final int dartsLeft;
  final int? favoriteDouble;
  final bool large;
  const CheckoutPanel({
    super.key,
    required this.remaining,
    required this.outMode,
    this.dartsLeft = 3,
    this.favoriteDouble,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final calc = CheckoutCalculator(outMode: outMode);
    final sug = calc.suggestions(remaining, dartsLeft: dartsLeft, favoriteDouble: favoriteDouble);
    if (sug.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in sug.take(large ? 3 : 4))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(
                width: large ? 130 : 110,
                child: Text(s.kind.label,
                    style: TextStyle(color: AppColors.textDim, fontSize: large ? 16 : 12)),
              ),
              for (final d in s.route.darts) ...[
                _DartChip(d, large: large),
                const SizedBox(width: 4),
              ],
            ]),
          ),
      ],
    );
  }
}

class _DartChip extends StatelessWidget {
  final DartThrow dart;
  final bool large;
  const _DartChip(this.dart, {this.large = false});
  @override
  Widget build(BuildContext context) {
    final color = dart.isTriple
        ? const Color(0xFFC0392B)
        : dart.isDouble
            ? AppColors.accentDim
            : AppColors.surfaceHigh;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 6 : 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Text(dart.label,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: large ? 20 : 14)),
    );
  }
}

/// Scoreboard für alle Spielarten. [tv] = große Darstellung für Fernseher/Beamer.
class ScoreboardView extends StatelessWidget {
  final MatchRecord match;
  final Map<String, int?> favoriteDoubles;
  final bool tv;
  final String? boardName;
  const ScoreboardView({
    super.key,
    required this.match,
    this.favoriteDoubles = const {},
    this.tv = false,
    this.boardName,
  });

  @override
  Widget build(BuildContext context) {
    if (match.x01 != null) return _X01Board(match: match, tv: tv, favs: favoriteDoubles, boardName: boardName);
    if (match.cricket != null) return _CricketBoard(match: match, tv: tv);
    if (match.clock != null) return _ClockBoard(match: match, tv: tv);
    return const SizedBox.shrink();
  }
}

class _X01Board extends StatelessWidget {
  final MatchRecord match;
  final bool tv;
  final Map<String, int?> favs;
  final String? boardName;
  const _X01Board({required this.match, required this.tv, required this.favs, this.boardName});

  @override
  Widget build(BuildContext context) {
    final x = match.x01!;
    final s = x.state;
    final preview = s.isFinished ? null : x.previewDraft(match.draft);
    final cards = <Widget>[
      for (var i = 0; i < match.players.length; i++)
        Expanded(
          child: _PlayerCard(
            key: Key('player-card-$i'),
            name: match.players[i].name,
            remaining: i == s.currentPlayer && preview != null && match.draft.isNotEmpty
                ? preview.remaining
                : s.remaining[i],
            active: !s.isFinished && i == s.currentPlayer,
            winner: s.winnerIndex == i,
            legs: s.legsWon[i],
            sets: s.setsWon[i],
            showSets: x.rules.format.usesSets,
            average: x.legAverage(i),
            matchAverage: _matchAverage(match, i),
            dartsInLeg: x.visits
                .where((v) => v.legNo == s.legNo && v.playerIndex == i)
                .fold<int>(0, (a, v) => a + v.dartsThrown),
            lastVisit: x.visits.where((v) => v.playerIndex == i).lastOrNull,
            draft: i == s.currentPlayer && !s.isFinished ? match.draft : const [],
            startedLeg: s.legStarter == i,
            tv: tv,
            favoriteDouble: favs[match.players[i].id],
            outMode: x.rules.outMode,
            dartsLeft: i == s.currentPlayer && preview != null ? preview.dartsLeft.clamp(1, 3) : 3,
          ),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(match: match, tv: tv, boardName: boardName),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                cards[i],
              ]
            ],
          ),
        ),
      ],
    );
  }

  static double? _matchAverage(MatchRecord m, int i) {
    final visits = m.x01!.visits.where((v) => v.playerIndex == i);
    final darts = visits.fold<int>(0, (a, v) => a + v.dartsThrown);
    if (darts == 0) return null;
    return visits.fold<int>(0, (a, v) => a + v.points) / darts * 3;
  }
}

class _Header extends StatelessWidget {
  final MatchRecord match;
  final bool tv;
  final String? boardName;
  const _Header({required this.match, required this.tv, this.boardName});
  @override
  Widget build(BuildContext context) {
    final x = match.x01;
    final parts = <String>[
      match.gameType.label,
      if (x != null) x.rules.label.split('·').last.trim(),
      if (x != null) x.rules.format.label,
      if (x != null) 'Leg ${x.state.legNo}',
      if (boardName != null) boardName!,
      if (match.status == MatchStatus.paused) '⏸ pausiert',
    ];
    return Text(parts.join('  ·  '),
        style: TextStyle(color: AppColors.textDim, fontSize: tv ? 20 : 13));
  }
}

class _PlayerCard extends StatelessWidget {
  final String name;
  final int remaining;
  final bool active;
  final bool winner;
  final int legs;
  final int sets;
  final bool showSets;
  final double? average;
  final double? matchAverage;
  final int dartsInLeg;
  final dynamic lastVisit;
  final List<DartThrow> draft;
  final bool startedLeg;
  final bool tv;
  final int? favoriteDouble;
  final OutMode outMode;
  final int dartsLeft;

  const _PlayerCard({
    super.key,
    required this.name,
    required this.remaining,
    required this.active,
    required this.winner,
    required this.legs,
    required this.sets,
    required this.showSets,
    required this.average,
    required this.matchAverage,
    required this.dartsInLeg,
    required this.lastVisit,
    required this.draft,
    required this.startedLeg,
    required this.tv,
    required this.favoriteDouble,
    required this.outMode,
    required this.dartsLeft,
  });

  @override
  Widget build(BuildContext context) {
    final scale = tv ? 1.7 : 1.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: active ? AppColors.surfaceHigh : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: winner ? AppColors.warning : (active ? AppColors.accent : const Color(0xFF22302A)),
            width: active || winner ? 2.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            PlayerAvatar(name, radius: 18 * scale),
            SizedBox(width: 8 * scale),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w700)),
            ),
            if (startedLeg) Icon(Icons.adjust, size: 16 * scale, color: AppColors.textDim),
            if (winner) Icon(Icons.emoji_events, color: AppColors.warning, size: 22 * scale),
          ]),
          SizedBox(height: 4 * scale),
          Center(
            child: FittedBox(
              child: Text('$remaining',
                  key: const Key('remaining'),
                  style: bigNumber.copyWith(
                      fontSize: 84 * scale,
                      color: active ? AppColors.accent : Colors.white)),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _Stat('Legs', '$legs', scale),
            if (showSets) ...[SizedBox(width: 16 * scale), _Stat('Sätze', '$sets', scale)],
          ]),
          SizedBox(height: 6 * scale),
          Wrap(spacing: 14 * scale, runSpacing: 2, children: [
            _Mini('Ø Leg', average == null ? '–' : average!.toStringAsFixed(1), scale),
            _Mini('Ø Match', matchAverage == null ? '–' : matchAverage!.toStringAsFixed(1), scale),
            _Mini('Darts', '$dartsInLeg', scale),
            _Mini('Letzte',
                lastVisit == null ? '–' : (lastVisit.bust ? 'Bust' : '${lastVisit.points}'), scale),
          ]),
          if (active) ...[
            SizedBox(height: 6 * scale),
            Wrap(spacing: 4, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Aufnahme:', style: TextStyle(color: AppColors.textDim, fontSize: 13 * scale)),
              for (final d in draft)
                Chip(
                  label: Text(d.label, style: TextStyle(fontSize: 13 * scale)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              if (draft.isEmpty) Text('–', style: TextStyle(fontSize: 13 * scale)),
            ]),
            SizedBox(height: 6 * scale),
            CheckoutPanel(
                remaining: remaining,
                outMode: outMode,
                dartsLeft: dartsLeft,
                favoriteDouble: favoriteDouble,
                large: tv),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final double scale;
  const _Stat(this.label, this.value, this.scale);
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: bigNumber.copyWith(fontSize: 30 * scale)),
        Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12 * scale)),
      ]);
}

class _Mini extends StatelessWidget {
  final String label;
  final String value;
  final double scale;
  const _Mini(this.label, this.value, this.scale);
  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
        TextSpan(text: '$label ', style: TextStyle(color: AppColors.textDim, fontSize: 12 * scale)),
        TextSpan(text: value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14 * scale)),
      ]));
}

class _CricketBoard extends StatelessWidget {
  final MatchRecord match;
  final bool tv;
  const _CricketBoard({required this.match, required this.tv});

  static String _marks(int n) => switch (n) { 0 => '', 1 => '/', 2 => '✕', _ => '⊗' };

  @override
  Widget build(BuildContext context) {
    final c = match.cricket!;
    final s = c.state;
    final scale = tv ? 1.6 : 1.0;
    final n = match.players.length;
    // Spalten: Spieler 0 | Zahl | Spieler 1..n-1
    Widget cell(String text,
            {bool bold = false, bool big = false, bool active = false, int flex = 2}) =>
        Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: (big ? 28 : 16) * scale,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                    color: active ? AppColors.accent : null)),
          ),
        );
    List<Widget> row(int Function(int player) marks, String middle, {bool points = false}) => [
          cell(points ? '${s.points[0]}' : _marks(marks(0)), big: !points, bold: points),
          cell(middle, bold: true, flex: 1),
          for (var i = 1; i < n; i++)
            cell(points ? '${s.points[i]}' : _marks(marks(i)), big: !points, bold: points),
        ];
    return Column(children: [
      Text('Cricket${c.cutThroat ? ' (Cut-Throat)' : ''}',
          style: TextStyle(color: AppColors.textDim, fontSize: 13 * scale)),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: EdgeInsets.all(12 * scale),
          child: Column(children: [
            Row(children: [
              for (var i = 0; i < n; i++) ...[
                if (i == 1) cell('', flex: 1),
                cell(match.players[i].name,
                    bold: true, active: s.currentPlayer == i && s.winnerIndex == null),
              ],
              if (n == 1) cell('', flex: 1),
            ]),
            for (final num in CricketMatch.numbers)
              Row(children: row((p) => s.marks[p][num]!, num == 25 ? 'Bull' : '$num')),
            const Divider(),
            Row(children: row((p) => 0, 'Pkt', points: true)),
          ]),
        ),
      ),
    ]);
  }
}

class _ClockBoard extends StatelessWidget {
  final MatchRecord match;
  final bool tv;
  const _ClockBoard({required this.match, required this.tv});
  @override
  Widget build(BuildContext context) {
    final s = match.clock!.state;
    final scale = tv ? 1.6 : 1.0;
    return Column(children: [
      Text('Around the Clock', style: TextStyle(color: AppColors.textDim, fontSize: 13 * scale)),
      const SizedBox(height: 8),
      for (var i = 0; i < match.players.length; i++)
        Card(
          child: Padding(
            padding: EdgeInsets.all(12 * scale),
            child: Row(children: [
              PlayerAvatar(match.players[i].name, radius: 18 * scale),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(match.players[i].name,
                      style: TextStyle(
                          fontSize: 18 * scale,
                          fontWeight: FontWeight.w700,
                          color: s.currentPlayer == i && s.winnerIndex == null ? AppColors.accent : null)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                      value: s.progress[i] / AroundTheClockMatch.targetCount, minHeight: 8),
                ]),
              ),
              SizedBox(width: 12 * scale),
              Text(
                  s.progress[i] >= AroundTheClockMatch.targetCount
                      ? '🏆'
                      : AroundTheClockMatch.targetLabel(s.progress[i]),
                  key: Key('clock-target-$i'),
                  style: bigNumber.copyWith(fontSize: 44 * scale, color: AppColors.accent)),
            ]),
          ),
        ),
    ]);
  }
}
