import '../models/dart_throw.dart';

/// Cricket (15-20 und Bull) mit Standard-Punktewertung ("Cut-Throat" optional).
///
/// Jeder Dart wird dem aktuellen Spieler zugeordnet; nach drei Darts wechselt
/// der Spieler. Der Zustand wird immer aus der Dart-Liste berechnet (Undo = letzten Dart entfernen).
class CricketMatch {
  static const List<int> numbers = [20, 19, 18, 17, 16, 15, 25];

  final List<String> playerIds;
  final bool cutThroat;
  final List<DartThrow> darts;
  late final CricketState state = _replay();

  CricketMatch({
    required this.playerIds,
    this.cutThroat = false,
    List<DartThrow> darts = const [],
  }) : darts = List.unmodifiable(darts) {
    if (playerIds.length < 2) throw ArgumentError('Cricket braucht mindestens 2 Spieler');
  }

  int get version => darts.length;

  CricketState _replay() {
    final n = playerIds.length;
    final marks = List.generate(n, (_) => {for (final x in numbers) x: 0});
    final points = List<int>.filled(n, 0);
    var current = 0;
    var dartsInVisit = 0;
    int? winner;

    bool closedByAll(int num) => marks.every((m) => m[num]! >= 3);

    for (final d in darts) {
      if (winner != null) throw StateError('Dart nach Spielende im Log');
      if (!d.isMiss && numbers.contains(d.number)) {
        final num = d.number;
        var add = d.multiplier;
        final have = marks[current][num]!;
        final toClose = (3 - have).clamp(0, 3);
        final closing = add < toClose ? add : toClose;
        marks[current][num] = have + closing;
        final extra = add - closing;
        if (extra > 0 && !closedByAll(num)) {
          // Punkten gegen alle Gegner, die das Feld noch nicht geschlossen haben.
          if (cutThroat) {
            for (var i = 0; i < n; i++) {
              if (i != current && marks[i][num]! < 3) points[i] += extra * num;
            }
          } else {
            final opponentsOpen = [
              for (var i = 0; i < n; i++)
                if (i != current && marks[i][num]! < 3) i
            ];
            if (opponentsOpen.isNotEmpty) points[current] += extra * num;
          }
        }
        // Sieg prüfen
        if (_hasWon(current, marks, points)) {
          winner = current;
        }
      }
      dartsInVisit++;
      if (winner == null && dartsInVisit == 3) {
        dartsInVisit = 0;
        current = (current + 1) % n;
      }
    }
    return CricketState(
      marks: marks,
      points: points,
      currentPlayer: current,
      dartsInVisit: dartsInVisit,
      winnerIndex: winner,
    );
  }

  bool _hasWon(int p, List<Map<int, int>> marks, List<int> points) {
    if (!numbers.every((x) => marks[p][x]! >= 3)) return false;
    for (var i = 0; i < playerIds.length; i++) {
      if (i == p) continue;
      if (cutThroat) {
        if (points[p] > points[i]) return false;
      } else {
        if (points[p] < points[i]) return false;
      }
    }
    return true;
  }

  CricketMatch addDart(DartThrow d, {int? expectedVersion}) {
    if (state.winnerIndex != null) throw StateError('Das Spiel ist bereits beendet');
    if (expectedVersion != null && expectedVersion != version) {
      throw StateError('Versionskonflikt: erwartet $expectedVersion, aktuell $version');
    }
    return CricketMatch(playerIds: playerIds, cutThroat: cutThroat, darts: [...darts, d]);
  }

  CricketMatch undo() {
    if (darts.isEmpty) throw StateError('Nichts rückgängig zu machen');
    return CricketMatch(
        playerIds: playerIds, cutThroat: cutThroat, darts: darts.sublist(0, darts.length - 1));
  }
}

class CricketState {
  final List<Map<int, int>> marks;
  final List<int> points;
  final int currentPlayer;
  final int dartsInVisit;
  final int? winnerIndex;
  const CricketState({
    required this.marks,
    required this.points,
    required this.currentPlayer,
    required this.dartsInVisit,
    required this.winnerIndex,
  });
}
