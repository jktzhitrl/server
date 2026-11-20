import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/ids.dart';
import '../../core/models/rules.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/services.dart';
import 'scoring_screen.dart';

/// Einstellungen für Spielmodus und Regeln (pro Turnier oder Begegnung).
class RulesEditor extends StatelessWidget {
  final GameType gameType;
  final X01Rules rules;
  final bool cutThroat;
  final bool skipAhead;
  final ValueChanged<GameType> onGameType;
  final ValueChanged<X01Rules> onRules;
  final ValueChanged<bool>? onCutThroat;
  final ValueChanged<bool>? onSkipAhead;
  final bool allowTraining;

  const RulesEditor({
    super.key,
    required this.gameType,
    required this.rules,
    required this.onGameType,
    required this.onRules,
    this.cutThroat = false,
    this.skipAhead = false,
    this.onCutThroat,
    this.onSkipAhead,
    this.allowTraining = true,
  });

  static const _bestOfOptions = [1, 3, 5, 7, 9, 11];

  @override
  Widget build(BuildContext context) {
    final x01 = gameType.isX01;
    final bestOf = rules.format.bestOfLegsCount;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final g in GameType.values)
          if (allowTraining || g != GameType.training)
            ChoiceChip(
              key: Key('game-${g.name}'),
              label: Text(g.label),
              selected: g == gameType,
              onSelected: (_) => onGameType(g),
            ),
      ]),
      if (x01) ...[
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<InMode>(
              value: rules.inMode,
              decoration: const InputDecoration(labelText: 'Einwurf'),
              items: const [
                DropdownMenuItem(value: InMode.straight, child: Text('Straight In')),
                DropdownMenuItem(value: InMode.double, child: Text('Double In')),
                DropdownMenuItem(value: InMode.master, child: Text('Master In')),
              ],
              onChanged: (v) => onRules(rules.copyWith(inMode: v)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<OutMode>(
              key: const Key('outMode'),
              value: rules.outMode,
              decoration: const InputDecoration(labelText: 'Auswurf'),
              items: const [
                DropdownMenuItem(value: OutMode.single, child: Text('Single Out')),
                DropdownMenuItem(value: OutMode.double, child: Text('Double Out')),
                DropdownMenuItem(value: OutMode.master, child: Text('Master Out')),
              ],
              onChanged: (v) => onRules(rules.copyWith(outMode: v)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (gameType != GameType.training)
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: rules.format.usesSets ? rules.format.setsToWin * 2 - 1 : 0,
                decoration: const InputDecoration(labelText: 'Sätze (Best of)'),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Nur Legs')),
                  for (final n in [3, 5, 7])
                    DropdownMenuItem(value: n, child: Text('Best of $n Sätze')),
                ],
                onChanged: (v) => onRules(rules.copyWith(
                    format: MatchFormat(
                        legsToWinSet: rules.format.legsToWinSet,
                        setsToWin: (v ?? 0) == 0 ? 1 : (v! ~/ 2 + 1)))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: const Key('bestOf'),
                value: _bestOfOptions.contains(bestOf) ? bestOf : null,
                decoration: InputDecoration(
                    labelText: rules.format.usesSets ? 'Legs je Satz (Best of)' : 'Legs (Best of)'),
                items: [
                  for (final n in _bestOfOptions)
                    DropdownMenuItem(value: n, child: Text('Best of $n')),
                ],
                onChanged: (v) => onRules(rules.copyWith(
                    format: MatchFormat(
                        legsToWinSet: (v ?? 3) ~/ 2 + 1, setsToWin: rules.format.setsToWin))),
              ),
            ),
          ]),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Wechselnder Anwurf'),
          value: rules.starterRule == StarterRule.alternating,
          onChanged: (v) =>
              onRules(rules.copyWith(starterRule: v ? StarterRule.alternating : StarterRule.fixed)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bull-Off im Entscheidungsleg'),
          value: rules.bullOffForDecider,
          onChanged: (v) => onRules(rules.copyWith(bullOffForDecider: v)),
        ),
      ],
      if (gameType == GameType.cricket && onCutThroat != null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cut-Throat'),
          value: cutThroat,
          onChanged: onCutThroat,
        ),
      if (gameType == GameType.aroundTheClock && onSkipAhead != null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Double/Triple springen weiter'),
          value: skipAhead,
          onChanged: onSkipAhead,
        ),
    ]);
  }
}

/// Freundschaftsspiel / Training starten.
class NewMatchScreen extends StatefulWidget {
  const NewMatchScreen({super.key});
  @override
  State<NewMatchScreen> createState() => _NewMatchScreenState();
}

class _NewMatchScreenState extends State<NewMatchScreen> {
  GameType _game = GameType.x501;
  X01Rules _rules = const X01Rules();
  bool _cutThroat = false;
  bool _skip = false;
  final List<TextEditingController> _names = [TextEditingController(), TextEditingController()];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final me = context.read<AppUser>();
    _names[0].text = me.displayName;
  }

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _solo => _game == GameType.training;

  Future<void> _start() async {
    final repo = context.read<AppRepository>();
    final user = context.read<AppUser>();
    final names = [
      for (final c in _names.take(_solo ? 1 : _names.length))
        if (c.text.trim().isNotEmpty) c.text.trim()
    ];
    if (names.length < (_solo || _game == GameType.aroundTheClock ? 1 : 2)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bitte Spielernamen eingeben.')));
      return;
    }
    setState(() => _busy = true);
    try {
      // Spieler anlegen bzw. vorhandene Profile (gleicher Name) wiederverwenden.
      final existing = await repo.watchPlayers().first;
      final players = <MatchPlayer>[];
      for (final n in names) {
        var p = existing.where((e) => e.name.toLowerCase() == n.toLowerCase()).firstOrNull;
        p ??= await repo.savePlayer(PlayerProfile(id: newId('pl'), name: n));
        players.add(MatchPlayer(p.id, p.name));
      }
      final m = await repo.createMatch(MatchFactory.create(
        gameType: _game,
        players: players,
        rules: _game == GameType.training
            ? _rules.copyWith(format: const MatchFormat(legsToWinSet: 1))
            : _rules,
        cutThroat: _cutThroat,
        skipAhead: _skip,
        scorerUid: user.uid,
      ));
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => ScoringScreen(matchId: m.id)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Neues Spiel')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        RulesEditor(
          gameType: _game,
          rules: _rules,
          cutThroat: _cutThroat,
          skipAhead: _skip,
          onGameType: (g) => setState(() => _game = g),
          onRules: (r) => setState(() => _rules = r),
          onCutThroat: (v) => setState(() => _cutThroat = v),
          onSkipAhead: (v) => setState(() => _skip = v),
        ),
        const SizedBox(height: 20),
        Text('Spieler', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < (_solo ? 1 : _names.length); i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              key: Key('playerName$i'),
              controller: _names[i],
              decoration: InputDecoration(labelText: 'Spieler ${i + 1}'),
            ),
          ),
        if (!_solo)
          Row(children: [
            TextButton.icon(
              onPressed: _names.length < 4
                  ? () => setState(() => _names.add(TextEditingController()))
                  : null,
              icon: const Icon(Icons.person_add),
              label: const Text('Spieler hinzufügen'),
            ),
          ]),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('startMatch'),
          onPressed: _busy ? null : _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Spiel starten'),
        ),
      ]),
    );
  }
}
