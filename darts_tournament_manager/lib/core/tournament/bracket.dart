import 'participant.dart';

/// Ein Platz in einer Begegnung.
class Slot {
  String? playerId;

  /// `true`, wenn hier nie ein Spieler eintreffen wird (Freilos).
  bool dead;
  Slot({this.playerId, this.dead = false});

  bool get filled => playerId != null;

  Map<String, dynamic> toJson() => {'playerId': playerId, 'dead': dead};
  factory Slot.fromJson(Map<String, dynamic> j) =>
      Slot(playerId: j['playerId'] as String?, dead: j['dead'] as bool? ?? false);
}

/// Eine Begegnung im Turnierbaum.
class BracketMatch {
  final String id;

  /// 'W' = Gewinnerbaum / K.-o., 'L' = Verliererbaum, 'G' = Grand Final.
  final String side;
  final int round;
  final int index;
  final Slot a;
  final Slot b;
  String? winnerId;
  String? loserId;
  int? scoreA;
  int? scoreB;

  /// Durch Freilos entschieden (kein Spiel nötig).
  bool isBye;

  /// Es wird nie ein Spiel stattfinden (z. B. Grand-Final-Reset nicht nötig).
  bool dead;
  String? winnerToId;
  int winnerToSlot;
  String? loserToId;
  int loserToSlot;

  BracketMatch({
    required this.id,
    required this.side,
    required this.round,
    required this.index,
    Slot? a,
    Slot? b,
    this.winnerId,
    this.loserId,
    this.scoreA,
    this.scoreB,
    this.isBye = false,
    this.dead = false,
    this.winnerToId,
    this.winnerToSlot = 0,
    this.loserToId,
    this.loserToSlot = 0,
  })  : a = a ?? Slot(),
        b = b ?? Slot();

  bool get isResolved => winnerId != null || dead;

  /// Beide Spieler stehen fest und es ist noch kein Ergebnis eingetragen.
  bool get isPlayable => !isResolved && a.filled && b.filled;

  List<String> get playerIds => [if (a.filled) a.playerId!, if (b.filled) b.playerId!];

  Map<String, dynamic> toJson() => {
        'id': id,
        'side': side,
        'round': round,
        'index': index,
        'a': a.toJson(),
        'b': b.toJson(),
        'winnerId': winnerId,
        'loserId': loserId,
        'scoreA': scoreA,
        'scoreB': scoreB,
        'isBye': isBye,
        'dead': dead,
        'winnerToId': winnerToId,
        'winnerToSlot': winnerToSlot,
        'loserToId': loserToId,
        'loserToSlot': loserToSlot,
      };

  factory BracketMatch.fromJson(Map<String, dynamic> j) => BracketMatch(
        id: j['id'] as String,
        side: j['side'] as String,
        round: (j['round'] as num).toInt(),
        index: (j['index'] as num).toInt(),
        a: Slot.fromJson(Map<String, dynamic>.from(j['a'] as Map)),
        b: Slot.fromJson(Map<String, dynamic>.from(j['b'] as Map)),
        winnerId: j['winnerId'] as String?,
        loserId: j['loserId'] as String?,
        scoreA: (j['scoreA'] as num?)?.toInt(),
        scoreB: (j['scoreB'] as num?)?.toInt(),
        isBye: j['isBye'] as bool? ?? false,
        dead: j['dead'] as bool? ?? false,
        winnerToId: j['winnerToId'] as String?,
        winnerToSlot: (j['winnerToSlot'] as num?)?.toInt() ?? 0,
        loserToId: j['loserToId'] as String?,
        loserToSlot: (j['loserToSlot'] as num?)?.toInt() ?? 0,
      );
}

class BracketError extends StateError {
  BracketError(super.message);
}

enum BracketType { single, double }

/// Turnierbaum (Single oder Double Elimination) mit automatischem
/// Rundenfortschritt und Freilos-Behandlung.
class Bracket {
  final BracketType type;
  final List<BracketMatch> matches;
  final Map<String, BracketMatch> _byId;

  Bracket._(this.type, this.matches) : _byId = {for (final m in matches) m.id: m};

  /// Single Elimination aus einer Positionsliste (Länge = Zweierpotenz,
  /// Paare 2i/2i+1 treffen in Runde 1 aufeinander; `null` = Freilos).
  factory Bracket.singleElimination(List<Participant?> positions) {
    final b = _build(positions, double: false);
    b._settle();
    return b;
  }

  /// Double Elimination (Gewinner-, Verliererbaum, Grand Final mit Reset).
  factory Bracket.doubleElimination(List<Participant?> positions) {
    final b = _build(positions, double: true);
    b._settle();
    return b;
  }

  factory Bracket.fromJson(Map<String, dynamic> j) => Bracket._(
        BracketType.values.byName(j['type'] as String),
        (j['matches'] as List)
            .map((e) => BracketMatch.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'matches': matches.map((m) => m.toJson()).toList(),
      };

  BracketMatch match(String id) => _byId[id] ?? (throw BracketError('Unbekannte Begegnung $id'));

  static String _id(String side, int round, int index) => '$side-r$round-m$index';

  static Bracket _build(List<Participant?> positions, {required bool double}) {
    final size = positions.length;
    if (size < 2 || (size & (size - 1)) != 0) {
      throw ArgumentError('Positionsliste muss Zweierpotenz >= 2 sein');
    }
    if (positions.whereType<Participant>().length < 2) {
      throw ArgumentError('Mindestens 2 Teilnehmer nötig');
    }
    var k = 0;
    while ((1 << k) < size) {
      k++;
    }
    final all = <BracketMatch>[];
    final byId = <String, BracketMatch>{};
    BracketMatch add(String side, int round, int index) {
      final m = BracketMatch(id: _id(side, round, index), side: side, round: round, index: index);
      all.add(m);
      byId[m.id] = m;
      return m;
    }

    // Gewinnerbaum
    for (var r = 1; r <= k; r++) {
      final count = size >> r;
      for (var i = 0; i < count; i++) {
        add('W', r, i);
      }
    }
    for (var r = 1; r < k; r++) {
      final count = size >> r;
      for (var i = 0; i < count; i++) {
        final m = byId[_id('W', r, i)]!;
        m.winnerToId = _id('W', r + 1, i ~/ 2);
        m.winnerToSlot = i % 2;
      }
    }
    for (var i = 0; i < size ~/ 2; i++) {
      final m = byId[_id('W', 1, i)]!;
      for (var s = 0; s < 2; s++) {
        final p = positions[2 * i + s];
        final slot = s == 0 ? m.a : m.b;
        if (p == null) {
          slot.dead = true;
        } else {
          slot.playerId = p.id;
        }
      }
    }

    if (double) {
      // Verliererbaum
      final lbRounds = k >= 2 ? 2 * (k - 1) : 0;
      int lbCount(int j) => size >> ((j + 1) ~/ 2 + 1);
      for (var j = 1; j <= lbRounds; j++) {
        for (var i = 0; i < lbCount(j); i++) {
          add('L', j, i);
        }
      }
      void loserTo(BracketMatch from, String toId, int slot) {
        from.loserToId = toId;
        from.loserToSlot = slot;
      }

      for (var i = 0; i < lbCount(1); i++) {
        loserTo(byId[_id('W', 1, 2 * i)]!, _id('L', 1, i), 0);
        loserTo(byId[_id('W', 1, 2 * i + 1)]!, _id('L', 1, i), 1);
      }
      for (var j = 1; j <= lbRounds; j++) {
        for (var i = 0; i < lbCount(j); i++) {
          final m = byId[_id('L', j, i)]!;
          if (j < lbRounds) {
            if ((j + 1).isEven) {
              // Folgerunde ist "gerade": Sieger trifft auf WB-Verlierer (Slot a).
              m.winnerToId = _id('L', j + 1, i);
              m.winnerToSlot = 0;
            } else {
              m.winnerToId = _id('L', j + 1, i ~/ 2);
              m.winnerToSlot = i % 2;
            }
          }
          if (j.isEven) {
            final mround = j ~/ 2 + 1; // WB-Runde, deren Verlierer hier einsteigen
            final cnt = lbCount(j);
            // Gegenläufige Reihenfolge in jeder zweiten Runde vermeidet frühe Rückspiele.
            final src = (mround.isEven) ? cnt - 1 - i : i;
            loserTo(byId[_id('W', mround, src)]!, m.id, 1);
          }
        }
      }
      final g1 = add('G', 1, 0);
      final g2 = add('G', 2, 0);
      final wbFinal = byId[_id('W', k, 0)]!;
      wbFinal.winnerToId = g1.id;
      wbFinal.winnerToSlot = 0;
      if (lbRounds == 0) {
        loserTo(wbFinal, g1.id, 1);
      } else {
        final lbFinal = byId[_id('L', lbRounds, 0)]!;
        lbFinal.winnerToId = g1.id;
        lbFinal.winnerToSlot = 1;
      }
      g2.dead = false;
    }
    return Bracket._(double ? BracketType.double : BracketType.single, all);
  }

  // ---------------------------------------------------------------- Fortschritt

  void _fill(String? toId, int slot, String? playerId) {
    if (toId == null) return;
    final t = match(toId);
    final s = slot == 0 ? t.a : t.b;
    if (playerId == null) {
      s.dead = true;
    } else {
      s.playerId = playerId;
      s.dead = false;
    }
  }

  /// Führt Freilos-Auflösungen und Weitergaben bis zum Fixpunkt aus.
  void _settle() {
    var changed = true;
    while (changed) {
      changed = false;
      for (final m in matches) {
        if (m.isResolved || m.side == 'G' && m.id == 'G-r2-m0') continue;
        if (m.a.dead && m.b.dead) {
          m.dead = true;
          _fill(m.winnerToId, m.winnerToSlot, null);
          _fill(m.loserToId, m.loserToSlot, null);
          changed = true;
        } else if (m.a.dead && m.b.filled) {
          _resolveBye(m, m.b.playerId!);
          changed = true;
        } else if (m.b.dead && m.a.filled) {
          _resolveBye(m, m.a.playerId!);
          changed = true;
        }
      }
    }
  }

  void _resolveBye(BracketMatch m, String winner) {
    m.winnerId = winner;
    m.isBye = true;
    _fill(m.winnerToId, m.winnerToSlot, winner);
    _fill(m.loserToId, m.loserToSlot, null);
  }

  /// Trägt ein Ergebnis ein und führt die Sieger (und im Double-Elimination
  /// auch die Verlierer) automatisch in die nächsten Begegnungen weiter.
  ///
  /// Eine Korrektur eines bereits eingetragenen Ergebnisses ist nur möglich,
  /// solange die Folgebegegnungen noch nicht gespielt wurden.
  void reportResult(String matchId, String winnerId, {int? scoreA, int? scoreB}) {
    final m = match(matchId);
    if (m.dead) throw BracketError('Diese Begegnung findet nicht statt');
    if (!m.a.filled || !m.b.filled) {
      throw BracketError('Die Spieler dieser Begegnung stehen noch nicht fest');
    }
    if (m.isBye) throw BracketError('Freilos-Begegnungen haben kein Ergebnis');
    if (winnerId != m.a.playerId && winnerId != m.b.playerId) {
      throw BracketError('Sieger muss einer der beiden Spieler sein');
    }
    final loser = winnerId == m.a.playerId ? m.b.playerId! : m.a.playerId!;
    if (m.winnerId != null) {
      // Korrektur: nur wenn Folgespiele noch offen sind.
      _assertDownstreamOpen(m);
    }
    m.winnerId = winnerId;
    m.loserId = loser;
    m.scoreA = scoreA;
    m.scoreB = scoreB;

    if (m.side == 'G') {
      _afterGrandFinal(m);
    } else {
      _fill(m.winnerToId, m.winnerToSlot, winnerId);
      _fill(m.loserToId, m.loserToSlot, loser);
    }
    _settle();
  }

  void _assertDownstreamOpen(BracketMatch m) {
    for (final id in [m.winnerToId, m.loserToId]) {
      if (id == null) continue;
      final t = match(id);
      if (t.winnerId != null && !t.isBye) {
        throw BracketError(
            'Korrektur nicht möglich: Folgebegegnung ${t.id} wurde bereits gespielt');
      }
    }
    if (m.id == 'G-r1-m0') {
      final g2 = match('G-r2-m0');
      if (g2.winnerId != null) {
        throw BracketError('Korrektur nicht möglich: Grand-Final-Reset wurde bereits gespielt');
      }
    }
  }

  void _afterGrandFinal(BracketMatch m) {
    if (m.id != 'G-r1-m0') return;
    final g2 = match('G-r2-m0');
    if (m.winnerId == m.a.playerId) {
      // Gewinnerbaum-Sieger gewinnt: kein Reset nötig.
      g2.dead = true;
      g2.a.playerId = null;
      g2.b.playerId = null;
    } else {
      g2.dead = false;
      g2.a.playerId = m.a.playerId;
      g2.b.playerId = m.b.playerId;
    }
  }

  // ------------------------------------------------------------------ Abfragen

  /// Gesamtsieger, sobald feststeht.
  String? get championId {
    if (type == BracketType.single) {
      final last = matches.where((m) => m.side == 'W').reduce((x, y) => x.round >= y.round ? x : y);
      return last.winnerId;
    }
    final g1 = match('G-r1-m0');
    final g2 = match('G-r2-m0');
    if (g1.winnerId == null) return null;
    if (g1.winnerId == g1.a.playerId) return g1.winnerId;
    return g2.winnerId;
  }

  bool get isComplete => championId != null;

  int roundsOf(String side) =>
      matches.where((m) => m.side == side).fold(0, (a, m) => m.round > a ? m.round : a);

  List<BracketMatch> roundMatches(String side, int round) =>
      matches.where((m) => m.side == side && m.round == round).toList()
        ..sort((x, y) => x.index.compareTo(y.index));

  /// Alle Begegnungen, die jetzt gespielt werden können, in Spielreihenfolge.
  List<BracketMatch> get playable {
    const sideOrder = {'W': 0, 'L': 1, 'G': 2};
    final list = matches.where((m) => m.isPlayable).toList()
      ..sort((x, y) {
        final c = x.round.compareTo(y.round);
        if (c != 0) return c;
        final s = sideOrder[x.side]!.compareTo(sideOrder[y.side]!);
        return s != 0 ? s : x.index.compareTo(y.index);
      });
    return list;
  }

  /// Die nächste Begegnung eines Spielers (oder `null`).
  BracketMatch? nextMatchFor(String playerId) {
    for (final m in playable) {
      if (m.playerIds.contains(playerId)) return m;
    }
    return null;
  }

  /// Ist der Spieler noch im Turnier?
  bool isEliminated(String playerId) {
    final inGame = matches.any((m) => !m.isResolved && m.playerIds.contains(playerId));
    if (inGame) return false;
    // Noch nicht eingesetzt, aber unterwegs (wartet auf Gegner)?
    for (final m in matches) {
      if (m.isResolved) continue;
      if (m.a.playerId == playerId || m.b.playerId == playerId) return false;
    }
    return championId != playerId;
  }

  /// Anzeigename einer Runde.
  String roundLabel(String side, int round) {
    if (side == 'G') return round == 1 ? 'Grand Final' : 'Grand Final (Reset)';
    final total = roundsOf(side);
    if (side == 'W') {
      final left = total - round;
      if (left == 0) return type == BracketType.double ? 'Gewinner-Finale' : 'Finale';
      if (left == 1) return 'Halbfinale';
      if (left == 2) return 'Viertelfinale';
      return 'Runde $round';
    }
    if (round == total) return 'Verlierer-Finale';
    return 'Verlierer-Runde $round';
  }
}
