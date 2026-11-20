import 'round_robin.dart';

/// Ein Dartboard (Spielfeld) mit aktuell zugewiesener Begegnung.
class Board {
  final String id;
  final String name;
  final String? currentMatchId;
  const Board({required this.id, required this.name, this.currentMatchId});
  bool get isFree => currentMatchId == null;
}

class BoardAssignment {
  final String matchId;
  final String boardId;
  const BoardAssignment(this.matchId, this.boardId);
}

/// Eine zuweisbare Begegnung.
class PendingMatch {
  final String id;
  final int round;
  final List<String> playerIds;
  const PendingMatch(this.id, this.round, this.playerIds);

  factory PendingMatch.fromFixture(Fixture f) => PendingMatch(f.id, f.round, f.playerIds);
}

/// Weist freie Boards den nächsten spielbaren Begegnungen zu.
///
/// Regeln: Es werden nur Begegnungen vergeben, deren Spieler gerade nicht
/// spielen und mindestens [minRest] Pause hatten. Frühere Runden haben Vorrang.
class BoardScheduler {
  final Duration minRest;
  const BoardScheduler({this.minRest = const Duration(minutes: 5)});

  /// [playingNow]: Spieler in laufenden Begegnungen. [lastFinished]: Zeitpunkt
  /// des letzten Spielendes je Spieler.
  List<BoardAssignment> assign({
    required List<PendingMatch> ready,
    required List<Board> boards,
    Set<String> playingNow = const {},
    Map<String, DateTime> lastFinished = const {},
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final free = boards.where((b) => b.isFree).toList();
    final busy = {...playingNow};
    final queue = [...ready]..sort((a, b) => a.round.compareTo(b.round));
    final out = <BoardAssignment>[];
    for (final m in queue) {
      if (free.isEmpty) break;
      if (m.playerIds.any(busy.contains)) continue;
      final rested = m.playerIds.every((p) {
        final last = lastFinished[p];
        return last == null || t.difference(last) >= minRest;
      });
      if (!rested) continue;
      final board = free.removeAt(0);
      out.add(BoardAssignment(m.id, board.id));
      busy.addAll(m.playerIds);
    }
    return out;
  }

  /// Spieler, die noch in der Ruhepause sind (für die Anzeige "Pause bis ...").
  Map<String, Duration> restingPlayers(Map<String, DateTime> lastFinished, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final out = <String, Duration>{};
    lastFinished.forEach((p, last) {
      final left = minRest - t.difference(last);
      if (left > Duration.zero) out[p] = left;
    });
    return out;
  }
}
