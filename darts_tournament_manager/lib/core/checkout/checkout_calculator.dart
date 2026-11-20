import '../models/dart_throw.dart';
import '../models/rules.dart';
import '../x01/finish.dart';

/// Ein konkreter Checkout-Weg (1-3 Darts, letzter Dart beendet das Leg).
class CheckoutRoute {
  final List<DartThrow> darts;
  const CheckoutRoute(this.darts);

  int get total => darts.fold(0, (a, d) => a + d.score);
  DartThrow get finisher => darts.last;

  @override
  String toString() => darts.map((d) => d.label).join(' – ');

  @override
  bool operator ==(Object other) =>
      other is CheckoutRoute &&
      other.darts.length == darts.length &&
      Iterable<int>.generate(darts.length).every((i) => darts[i] == other.darts[i]);

  @override
  int get hashCode => Object.hashAll(darts);
}

enum CheckoutKind { standard, alternative, favoriteDouble, safe, fewestDarts }

extension CheckoutKindX on CheckoutKind {
  String get label => switch (this) {
        CheckoutKind.standard => 'Standard',
        CheckoutKind.alternative => 'Alternative',
        CheckoutKind.favoriteDouble => 'Lieblingsdoppel',
        CheckoutKind.safe => 'Sichere Route',
        CheckoutKind.fewestDarts => 'Wenigste Darts',
      };
}

class CheckoutSuggestion {
  final CheckoutKind kind;
  final CheckoutRoute route;
  const CheckoutSuggestion(this.kind, this.route);
}

/// Regelbasierter Checkout-Rechner.
///
/// Der Rechner enumeriert ALLE regelkonformen Wege (jede Kombination aus bis zu
/// drei Darts, deren Summe den Rest ergibt und deren letzter Dart ein gültiger
/// Finish-Dart ist, ohne dass ein früherer Dart bustet) und bewertet sie mit
/// einer nachvollziehbaren Kostenfunktion. Die kleine Tabelle [_curated]
/// enthält nur bekannte Profi-Routen als Präferenz; jede Eintragung wird in den
/// Tests gegen die Regeln validiert.
class CheckoutCalculator {
  final OutMode outMode;
  const CheckoutCalculator({this.outMode = OutMode.double});

  /// Bevorzugte Reihenfolge der Abschlussdoppel (niedrig = besser): Die
  /// "Halbierungskette" D20-D10-D5, D16-D8-D4-D2-D1 zuerst.
  static const List<int> _doubleRank = [20, 16, 8, 12, 10, 18, 4, 14, 6, 2, 24, 22];

  static int _doubleCost(DartThrow d) {
    if (d.isBull && d.isDouble) return 4;
    if (d.isDouble) {
      final i = _doubleRank.indexOf(d.number);
      return i >= 0 ? (i < 3 ? i : 3 + (i - 3) ~/ 2) : 8;
    }
    if (d.isTriple) return 5;
    return 6;
  }

  /// Kosten eines Setup-Darts (kleiner = bevorzugt): hohe Triples zuerst,
  /// dann hohe Singles; Doppel und Bull als Setup sind unnatürlich.
  static int _setupCost(DartThrow d) {
    if (d.isTriple) {
      if (d.number >= 15) return 20 - d.number; // T20=0 .. T15=5
      return 9;
    }
    if (d.isDouble) return d.isBull ? 14 : 20;
    if (d.isBull) return 14;
    if (d.number >= 15) return 5;
    if (d.number >= 10) return 6;
    return 8;
  }

  static int _routeCost(List<DartThrow> r) {
    var c = r.length * 100 + _doubleCost(r.last) * 5;
    for (var i = 0; i < r.length - 1; i++) {
      c += _setupCost(r[i]);
    }
    return c;
  }

  // Bekannte Profi-Routen (nur Präferenzen; werden in Tests validiert).
  static final Map<int, List<String>> _curated = {
    170: ['T20', 'T20', 'Bull'],
    167: ['T20', 'T19', 'Bull'],
    164: ['T20', 'T18', 'Bull'],
    161: ['T20', 'T17', 'Bull'],
    160: ['T20', 'T20', 'D20'],
    141: ['T20', 'T19', 'D12'],
    121: ['T20', 'T11', 'D14'],
    100: ['T20', 'D20'],
    80: ['T20', 'D10'],
    64: ['T16', 'D8'],
    50: ['Bull'],
  };

  static final Map<String, List<CheckoutRoute>> _cache = {};

  /// Alle regelkonformen Wege mit höchstens [dartsLeft] Darts, beste zuerst.
  List<CheckoutRoute> allRoutes(int score, {int dartsLeft = 3}) {
    if (score < 1 || score > maxCheckout(outMode)) return const [];
    final key = '${outMode.name}/$score/$dartsLeft';
    return _cache.putIfAbsent(key, () {
      final routes = <CheckoutRoute>[];
      for (var n = 1; n <= dartsLeft.clamp(1, 3); n++) {
        _enumerate(score, n, <DartThrow>[], routes);
      }
      routes.sort((a, b) {
        final c = _routeCost(a.darts).compareTo(_routeCost(b.darts));
        return c != 0 ? c : a.toString().compareTo(b.toString());
      });
      return List.unmodifiable(routes);
    });
  }

  void _enumerate(int remaining, int dartsLeft, List<DartThrow> prefix, List<CheckoutRoute> out) {
    if (dartsLeft == 1) {
      for (final d in DartThrow.allScoring) {
        if (d.score == remaining && isValidFinishDart(d, outMode)) {
          out.add(CheckoutRoute([...prefix, d]));
        }
      }
      return;
    }
    final min = minimumRemaining(outMode);
    for (final d in DartThrow.allScoring) {
      // Kanonische Reihenfolge: Setup-Darts mit nicht-steigendem Punktwert
      // (jede andere Reihenfolge ist nur eine Permutation desselben Weges).
      if (prefix.isNotEmpty && d.score > prefix.last.score) continue;
      final rest = remaining - d.score;
      if (rest < min) continue;
      if (!canFinishWithDarts(rest, dartsLeft - 1, outMode)) continue;
      _enumerate(rest, dartsLeft - 1, [...prefix, d], out);
    }
  }

  /// Ist [score] mit [dartsLeft] Darts beendbar?
  bool isCheckoutable(int score, {int dartsLeft = 3}) =>
      canFinishWithin(score, dartsLeft, outMode);

  /// Beste ("Standard") Route.
  CheckoutRoute? standardRoute(int score, {int dartsLeft = 3}) {
    final all = allRoutes(score, dartsLeft: dartsLeft);
    if (all.isEmpty) return null;
    final fewest = all.first.darts.length;
    if (outMode == OutMode.double) {
      final cur = _curated[score];
      if (cur != null && cur.length <= dartsLeft) {
        final r = CheckoutRoute(cur.map(DartThrow.parse).toList());
        // Nur verwenden, wenn die Route regelkonform ist und nicht länger als nötig.
        if (all.contains(r) && r.darts.length == fewest) return r;
      }
    }
    return all.first;
  }

  /// Mehrere Varianten für die Anzeige, ohne Duplikate.
  ///
  /// [favoriteDouble] ist die Nummer des Lieblingsdoppels (25 = Bull).
  List<CheckoutSuggestion> suggestions(
    int score, {
    int dartsLeft = 3,
    int? favoriteDouble,
  }) {
    final all = allRoutes(score, dartsLeft: dartsLeft);
    if (all.isEmpty) return const [];
    final result = <CheckoutSuggestion>[];
    final seen = <CheckoutRoute>{};
    void add(CheckoutKind k, CheckoutRoute? r) {
      if (r == null || seen.contains(r)) return;
      seen.add(r);
      result.add(CheckoutSuggestion(k, r));
    }

    final std = standardRoute(score, dartsLeft: dartsLeft)!;
    add(CheckoutKind.standard, std);

    // Wenigste Darts (nach Kosten bester Weg mit minimaler Dartzahl).
    // (Nur wenn sie sich vom Standard unterscheidet - der Standard nutzt
    // ohnehin immer die minimale Dartzahl.)
    final fewestLen = all.first.darts.length;
    if (std.darts.length > fewestLen) {
      add(CheckoutKind.fewestDarts, all.first);
    }

    // Lieblingsdoppel.
    if (favoriteDouble != null) {
      final fav = all.where((r) => r.finisher.isDouble && r.finisher.number == favoriteDouble);
      if (fav.isNotEmpty) add(CheckoutKind.favoriteDouble, fav.first);
    }

    // Sichere Route: keine Triples/Bulls als Setup, Rest auf gutem Doppel.
    add(CheckoutKind.safe, _safeRoute(all));

    // Alternative: bester Weg mit anderem Abschlussfeld als Standard.
    final alt = all.where((r) => r.finisher != std.finisher && r.darts.length <= std.darts.length + 1);
    add(CheckoutKind.alternative, alt.isEmpty ? null : alt.first);

    return result;
  }

  CheckoutRoute? _safeRoute(List<CheckoutRoute> all) {
    bool plain(CheckoutRoute r) => r.darts
        .take(r.darts.length - 1)
        .every((d) => d.isSingle && !d.isBull);
    final candidates = all.where((r) => plain(r) && !r.finisher.isBull).toList();
    if (candidates.isEmpty) return null;
    // Bevorzuge gute Abschlussdoppel, dann wenige Darts.
    candidates.sort((a, b) {
      final c = _doubleCost(a.finisher).compareTo(_doubleCost(b.finisher));
      return c != 0 ? c : a.darts.length.compareTo(b.darts.length);
    });
    return candidates.first;
  }
}
