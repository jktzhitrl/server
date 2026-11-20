/// Wie ein Leg begonnen werden muss.
enum InMode { straight, double, master }

/// Wie ein Leg beendet werden muss.
enum OutMode { single, double, master }

/// Unterstützte Spielarten.
enum GameType { x301, x501, x701, x1001, cricket, aroundTheClock, training }

extension GameTypeX on GameType {
  /// Startwert bei X01-Spielen (Training = 501 Einzelspieler).
  int? get startScore => switch (this) {
        GameType.x301 => 301,
        GameType.x501 => 501,
        GameType.x701 => 701,
        GameType.x1001 => 1001,
        GameType.training => 501,
        _ => null,
      };

  bool get isX01 => startScore != null;

  String get label => switch (this) {
        GameType.x301 => '301',
        GameType.x501 => '501',
        GameType.x701 => '701',
        GameType.x1001 => '1001',
        GameType.cricket => 'Cricket',
        GameType.aroundTheClock => 'Around the Clock',
        GameType.training => 'Training',
      };
}

/// Wer das Leg beginnt.
enum StarterRule {
  /// Anwurf wechselt in jedem Leg.
  alternating,

  /// Der gleiche Spieler beginnt jedes Leg.
  fixed,
}

/// Format (Best-of) eines Matches. `legsToWinSet` Legs gewinnen einen Satz,
/// `setsToWin` Sätze gewinnen das Match. Ohne Sätze: `setsToWin == 1`.
class MatchFormat {
  final int legsToWinSet;
  final int setsToWin;

  const MatchFormat({required this.legsToWinSet, this.setsToWin = 1})
      : assert(legsToWinSet >= 1),
        assert(setsToWin >= 1);

  /// "Best of N Legs" (N ungerade empfohlen) ohne Sätze.
  factory MatchFormat.bestOfLegs(int n) {
    if (n < 1) throw ArgumentError.value(n, 'n', 'muss >= 1 sein');
    return MatchFormat(legsToWinSet: n ~/ 2 + 1);
  }

  /// "Best of S Sätze, je Best of L Legs".
  factory MatchFormat.bestOfSets({required int sets, required int legsPerSet}) =>
      MatchFormat(legsToWinSet: legsPerSet ~/ 2 + 1, setsToWin: sets ~/ 2 + 1);

  bool get usesSets => setsToWin > 1;

  /// Maximale Anzahl Legs, wenn nur Legs gespielt werden (Best-of-Länge).
  int get bestOfLegsCount => legsToWinSet * 2 - 1;

  Map<String, dynamic> toJson() =>
      {'legsToWinSet': legsToWinSet, 'setsToWin': setsToWin};

  factory MatchFormat.fromJson(Map<String, dynamic> j) => MatchFormat(
        legsToWinSet: (j['legsToWinSet'] as num).toInt(),
        setsToWin: (j['setsToWin'] as num?)?.toInt() ?? 1,
      );

  String get label => usesSets
      ? 'First to $setsToWin Sätze (je $legsToWinSet Legs)'
      : 'First to $legsToWinSet Legs';
}

/// Alle Regeln eines X01-Matches (pro Turnier oder Begegnung einstellbar).
class X01Rules {
  final int startScore;
  final InMode inMode;
  final OutMode outMode;
  final MatchFormat format;
  final StarterRule starterRule;

  /// Entscheidungsleg wird per Bull-Off ausgespielt (Anwurf manuell wählbar).
  final bool bullOffForDecider;

  const X01Rules({
    this.startScore = 501,
    this.inMode = InMode.straight,
    this.outMode = OutMode.double,
    this.format = const MatchFormat(legsToWinSet: 2),
    this.starterRule = StarterRule.alternating,
    this.bullOffForDecider = false,
  });

  X01Rules copyWith({
    int? startScore,
    InMode? inMode,
    OutMode? outMode,
    MatchFormat? format,
    StarterRule? starterRule,
    bool? bullOffForDecider,
  }) =>
      X01Rules(
        startScore: startScore ?? this.startScore,
        inMode: inMode ?? this.inMode,
        outMode: outMode ?? this.outMode,
        format: format ?? this.format,
        starterRule: starterRule ?? this.starterRule,
        bullOffForDecider: bullOffForDecider ?? this.bullOffForDecider,
      );

  Map<String, dynamic> toJson() => {
        'startScore': startScore,
        'inMode': inMode.name,
        'outMode': outMode.name,
        'format': format.toJson(),
        'starterRule': starterRule.name,
        'bullOffForDecider': bullOffForDecider,
      };

  factory X01Rules.fromJson(Map<String, dynamic> j) => X01Rules(
        startScore: (j['startScore'] as num).toInt(),
        inMode: InMode.values.byName(j['inMode'] as String),
        outMode: OutMode.values.byName(j['outMode'] as String),
        format: MatchFormat.fromJson(Map<String, dynamic>.from(j['format'] as Map)),
        starterRule: StarterRule.values.byName(j['starterRule'] as String),
        bullOffForDecider: j['bullOffForDecider'] as bool? ?? false,
      );

  String get label =>
      '$startScore · ${inMode == InMode.straight ? 'Straight In' : inMode == InMode.double ? 'Double In' : 'Master In'}'
      ' / ${outMode == OutMode.single ? 'Single Out' : outMode == OutMode.double ? 'Double Out' : 'Master Out'}';
}
