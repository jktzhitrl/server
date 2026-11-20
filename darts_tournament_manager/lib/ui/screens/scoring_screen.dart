import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/permissions.dart';
import '../../core/models/dart_throw.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/services.dart';
import '../theme.dart';
import '../widgets/dartboard.dart';
import '../widgets/scoreboard.dart';
import '../widgets/total_keypad.dart';
import 'live_screen.dart';

enum _InputKind { board, buttons, total }

/// Score-Eingabe für den Schreiber. Beide Modi sind jederzeit umschaltbar:
///  * Modus A: jeder Dart einzeln (interaktive Scheibe oder Tasten)
///  * Modus B: nur Gesamtpunkte je Aufnahme
class ScoringScreen extends StatefulWidget {
  final String matchId;
  const ScoringScreen({super.key, required this.matchId});

  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  _InputKind _kind = _InputKind.board;
  Role? _tournamentRole;
  bool _roleLoaded = false;
  bool _busy = false;
  late final Stream<MatchRecord?> _stream;
  Map<String, int?> _favs = const {};

  @override
  void initState() {
    super.initState();
    _stream = context.read<AppRepository>().watchMatch(widget.matchId);
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final repo = context.read<AppRepository>();
    final user = context.read<AppUser>();
    final m = await repo.watchMatch(widget.matchId).first;
    if (m?.tournamentId != null) {
      _tournamentRole = await repo.memberRole(m!.tournamentId!, user.uid);
    }
    final players = await repo.watchPlayers().first;
    _favs = {for (final p in players) p.id: p.favoriteDouble};
    if (mounted) setState(() => _roleLoaded = true);
  }

  bool _canScore(MatchRecord m, AppUser user) {
    final role = effectiveRole(user.role, _tournamentRole);
    if (m.tournamentId == null) return role != Role.spectator; // Freundschaftsspiel
    return can(role, Permission.enterScores);
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: error ? AppColors.danger : null,
          duration: const Duration(seconds: 3)));
  }

  /// Führt eine Änderung atomar mit Versionsprüfung aus.
  Future<void> _apply(MatchRecord m, MatchRecord Function(MatchRecord c) change) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<AppRepository>().updateMatch(m.id, (c) {
        var next = change(c);
        if (next.isFinished && next.tournamentId == null && next.status == MatchStatus.live) {
          next = next.copyWith(status: MatchStatus.confirmed);
        }
        return next;
      }, expectedVersion: m.version);
    } on VersionConflict {
      _toast('Der Spielstand wurde auf einem anderen Gerät geändert und wurde neu geladen. Bitte erneut eingeben.',
          error: true);
    } on ArgumentError catch (e) {
      _toast('${e.message}', error: true);
    } on StateError catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('unavailable') || text.contains('network') || text.contains('offline')) {
        _toast(
            'Keine Verbindung zum Server – die Eingabe wurde NICHT gespeichert. Bitte erneut eingeben, sobald die Verbindung steht.',
            error: true);
      } else {
        _toast('Fehler: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addDart(MatchRecord m, DartThrow d) async {
    if (m.x01 != null) {
      await _apply(m, (c) {
        final x = c.x01!;
        final draft = [...c.draft, d];
        final pv = x.previewDraft(draft);
        if (pv.complete) {
          final ev = pv.evaluation!;
          if (ev.isBust) _toast('Bust! Aufnahme ungültig.', error: true);
          if (ev.isCheckout) _toast('Checkout! Leg gewonnen.');
          return c.copyWith(x01: x.submitDarts(draft), draft: const []);
        }
        return c.copyWith(draft: draft);
      });
    } else if (m.cricket != null) {
      await _apply(m, (c) => c.copyWith(cricket: c.cricket!.addDart(d)));
    } else if (m.clock != null) {
      await _apply(m, (c) => c.copyWith(clock: c.clock!.addDart(d)));
    }
  }

  Future<void> _submitTotal(MatchRecord m, TotalEntry e) => _apply(m, (c) {
        if (c.draft.isNotEmpty) {
          throw StateError('Es läuft eine Einzeldart-Aufnahme. Bitte erst abschließen oder rückgängig machen.');
        }
        final next = c.x01!.submitTotal(e.total,
            dartsUsed: e.dartsUsed, checkoutAttempts: e.checkoutAttempts, bust: e.bust);
        if (next.lastVisit!.bust) _toast('Bust! Aufnahme ungültig.', error: true);
        return c.copyWith(x01: next);
      });

  Future<void> _undo(MatchRecord m) => _apply(m, (c) {
        if (c.x01 != null) {
          if (c.draft.isNotEmpty) {
            return c.copyWith(draft: c.draft.sublist(0, c.draft.length - 1));
          }
          final next = c.copyWith(x01: c.x01!.undo());
          return next.status == MatchStatus.awaitingConfirmation
              ? next.copyWith(status: MatchStatus.live)
              : next;
        }
        if (c.cricket != null) return c.copyWith(cricket: c.cricket!.undo());
        return c.copyWith(clock: c.clock!.undo());
      });

  /// Letzte Aufnahme bearbeiten: sie wird zurückgenommen; Einzeldarts landen
  /// wieder in der laufenden Aufnahme und können korrigiert werden.
  Future<void> _editLast(MatchRecord m) => _apply(m, (c) {
        final x = c.x01!;
        final last = x.lastVisit;
        if (last == null) throw StateError('Es gibt noch keine Aufnahme.');
        if (c.draft.isNotEmpty) throw StateError('Bitte zuerst die laufende Aufnahme abschließen.');
        final next = c.copyWith(x01: x.undo(), draft: last.darts?.toList() ?? const []);
        if (last.darts == null) {
          _toast('Aufnahme entfernt – bitte neu eingeben (vorher: ${last.enteredTotal}).');
        }
        return next.status == MatchStatus.awaitingConfirmation
            ? next.copyWith(status: MatchStatus.live)
            : next;
      });

  Future<void> _togglePause(MatchRecord m) => _apply(
      m,
      (c) => c.copyWith(
          status: c.status == MatchStatus.paused ? MatchStatus.live : MatchStatus.paused));

  Future<void> _chooseStarter(MatchRecord m) async {
    final x = m.x01!;
    final idx = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Bull-Off – wer beginnt das Entscheidungsleg?'),
        children: [
          for (var i = 0; i < m.players.length; i++)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, i),
                child: Text(m.players[i].name, style: const TextStyle(fontSize: 18))),
        ],
      ),
    );
    if (idx == null) return;
    await _apply(m, (c) => c.copyWith(x01: c.x01!.withStarterOverride(x.state.legNo, idx)));
  }

  Future<void> _submitResult(MatchRecord m) async {
    try {
      await context.read<TournamentService>().submitResult(context.read<AppUser>(), m);
      _toast('Ergebnis zur Bestätigung übermittelt.');
    } on VersionConflict {
      _toast('Spielstand wurde zwischenzeitlich geändert.', error: true);
    } catch (e) {
      _toast('$e', error: true);
    }
  }

  Future<void> _confirm(MatchRecord m) async {
    try {
      await context.read<TournamentService>().confirmResult(context.read<AppUser>(), m);
      _toast('Ergebnis bestätigt, Turnier aktualisiert.');
    } catch (e) {
      _toast('$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    return StreamBuilder<MatchRecord?>(
      stream: _stream,
      builder: (context, snap) {
        final m = snap.data;
        if (!snap.hasData || !_roleLoaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (m == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Begegnung nicht gefunden')));
        }
        final canScore = _canScore(m, user);
        final canConfirm = can(effectiveRole(user.role, _tournamentRole), Permission.confirmResult);
        final x = m.x01;
        final needsStarter = x != null &&
            canScore &&
            x.rules.bullOffForDecider &&
            x.isDeciderLeg &&
            !x.starterOverrides.containsKey(x.state.legNo);
        final active = canScore && m.status != MatchStatus.paused && !m.isFinished && !_busy;

        final board = ScoreboardView(match: m, favoriteDoubles: _favs);
        final input = _buildInput(m, active, canScore);

        return Scaffold(
          appBar: AppBar(
            title: Text(m.players.map((p) => p.name).join(' – ')),
            actions: [
              IconButton(
                tooltip: 'TV-Modus',
                icon: const Icon(Icons.tv),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => LiveMatchScreen(matchId: m.id, tv: true))),
              ),
              if (canScore)
                IconButton(
                  tooltip: m.status == MatchStatus.paused ? 'Fortsetzen' : 'Pausieren',
                  icon: Icon(m.status == MatchStatus.paused ? Icons.play_arrow : Icons.pause),
                  onPressed: m.isFinished ? null : () => _togglePause(m),
                ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 900;
              final banner = _banner(m, canScore, canConfirm, needsStarter);
              final content = wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(children: [banner, board]))),
                      Expanded(
                          flex: 4,
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16), child: input)),
                    ])
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      banner,
                      board,
                      const SizedBox(height: 12),
                      input,
                    ]);
              return content;
            }),
          ),
        );
      },
    );
  }

  Widget _banner(MatchRecord m, bool canScore, bool canConfirm, bool needsStarter) {
    final items = <Widget>[];
    if (!canScore) {
      items.add(_note('Nur Ansicht – für die Eingabe fehlt die Berechtigung (Schreiber/Turnierleitung).',
          Icons.visibility));
    }
    if (m.status == MatchStatus.paused) {
      items.add(_note('Spiel pausiert', Icons.pause_circle));
    }
    if (needsStarter) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FilledButton.icon(
          key: const Key('bullOff'),
          icon: const Icon(Icons.adjust),
          label: const Text('Bull-Off: Anwurf festlegen'),
          onPressed: () => _chooseStarter(m),
        ),
      ));
    }
    if (m.isFinished) {
      items.add(Card(
        color: AppColors.accentDim,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🏆 Sieger: ${m.players[m.winnerIndex!].name}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (m.tournamentId != null) ...[
              const SizedBox(height: 8),
              if (m.status == MatchStatus.live && canScore)
                FilledButton(
                    key: const Key('submitResult'),
                    onPressed: () => _submitResult(m),
                    child: const Text('Ergebnis zur Bestätigung senden')),
              if (m.status == MatchStatus.awaitingConfirmation)
                canConfirm
                    ? FilledButton(
                        key: const Key('confirmResult'),
                        onPressed: () => _confirm(m),
                        child: const Text('Ergebnis bestätigen'))
                    : const Text('Wartet auf Bestätigung durch die Turnierleitung.'),
              if (m.status == MatchStatus.confirmed) const Text('Ergebnis bestätigt.'),
            ],
          ]),
        ),
      ));
      items.add(const SizedBox(height: 8));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
  }

  Widget _note(String text, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: ListTile(leading: Icon(icon, color: AppColors.warning), title: Text(text)),
        ),
      );

  Widget _buildInput(MatchRecord m, bool active, bool canScore) {
    final x = m.x01;
    final isX01 = x != null;
    final kinds = isX01
        ? const [_InputKind.board, _InputKind.buttons, _InputKind.total]
        : const [_InputKind.board, _InputKind.buttons];
    final kind = kinds.contains(_kind) ? _kind : _InputKind.board;
    final undoEnabled = canScore &&
        !_busy &&
        (m.draft.isNotEmpty ||
            (x?.visits.isNotEmpty ?? false) ||
            (m.cricket?.darts.isNotEmpty ?? false) ||
            (m.clock?.darts.isNotEmpty ?? false)) &&
        m.status != MatchStatus.confirmed;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<_InputKind>(
        key: const Key('inputKind'),
        segments: [
          const ButtonSegment(value: _InputKind.board, icon: Icon(Icons.track_changes), label: Text('Scheibe')),
          const ButtonSegment(value: _InputKind.buttons, icon: Icon(Icons.dialpad), label: Text('Darts')),
          if (isX01)
            const ButtonSegment(value: _InputKind.total, icon: Icon(Icons.pin), label: Text('Summe')),
        ],
        selected: {kind},
        onSelectionChanged: (s) => setState(() => _kind = s.first),
      ),
      const SizedBox(height: 12),
      if (kind == _InputKind.board)
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(children: [
              DartboardInput(enabled: active, onDart: (d) => _addDart(m, d)),
              const SizedBox(height: 8),
              OutlinedButton(
                  key: const Key('missButton'),
                  onPressed: active ? () => _addDart(m, DartThrow.miss) : null,
                  child: const Text('Miss (0)')),
            ]),
          ),
        ),
      if (kind == _InputKind.buttons) DartButtons(enabled: active, onDart: (d) => _addDart(m, d)),
      if (kind == _InputKind.total && x != null)
        TotalKeypad(
          // Rest des aktiven Spielers; bei laufender Einzeldart-Aufnahme gesperrt.
          remaining: x.state.remaining[x.state.currentPlayer],
          outMode: x.rules.outMode,
          enabled: active && m.draft.isEmpty,
          onSubmit: (e) => _submitTotal(m, e),
        ),
      if (kind == _InputKind.total && m.draft.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Es läuft eine Einzeldart-Aufnahme – bitte mit „Darts“/„Scheibe“ abschließen oder rückgängig machen.',
              style: TextStyle(color: AppColors.warning)),
        ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('undo'),
            icon: const Icon(Icons.undo),
            label: const Text('Rückgängig'),
            onPressed: undoEnabled ? () => _undo(m) : null,
          ),
        ),
        if (isX01) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('editLast'),
              icon: const Icon(Icons.edit),
              label: const Text('Letzte bearbeiten'),
              onPressed: undoEnabled && m.draft.isEmpty && x.visits.isNotEmpty ? () => _editLast(m) : null,
            ),
          ),
        ],
      ]),
    ]);
  }
}
