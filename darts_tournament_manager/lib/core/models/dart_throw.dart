/// Ein einzelner Dart auf der Scheibe.
///
/// Gültige Felder:
///  * Single/Double/Triple 1-20
///  * Outer Bull (25) = Single 25
///  * Bullseye (50)   = Double 25
///  * Miss (0)        = Multiplikator 0
class DartThrow {
  /// 0 = Miss, 1 = Single, 2 = Double, 3 = Triple.
  final int multiplier;

  /// 1-20 oder 25 (Bull). Bei Miss immer 0.
  final int number;

  const DartThrow._(this.multiplier, this.number);

  /// Erzeugt einen validierten Wurf.
  factory DartThrow(int multiplier, int number) {
    if (multiplier == 0) return miss;
    if (multiplier < 1 || multiplier > 3) {
      throw ArgumentError.value(multiplier, 'multiplier', 'muss 0..3 sein');
    }
    if (number == 25) {
      if (multiplier == 3) {
        throw ArgumentError('Es gibt kein Triple-Bull');
      }
      return DartThrow._(multiplier, 25);
    }
    if (number < 1 || number > 20) {
      throw ArgumentError.value(number, 'number', 'muss 1..20 oder 25 sein');
    }
    return DartThrow._(multiplier, number);
  }

  static const DartThrow miss = DartThrow._(0, 0);
  static const DartThrow outerBull = DartThrow._(1, 25);
  static const DartThrow bullseye = DartThrow._(2, 25);

  factory DartThrow.single(int n) => DartThrow(1, n);
  factory DartThrow.double(int n) => DartThrow(2, n);
  factory DartThrow.triple(int n) => DartThrow(3, n);

  /// Parst Notationen wie `T20`, `D16`, `S5`, `25`, `BULL`, `DB`, `MISS`.
  factory DartThrow.parse(String text) {
    final t = text.trim().toUpperCase();
    if (t == 'MISS' || t == '0' || t == 'M') return miss;
    if (t == 'BULL' || t == 'DB' || t == 'BE' || t == '50') return bullseye;
    if (t == 'OB' || t == 'SB' || t == '25') return outerBull;
    final m = RegExp(r'^([SDT])(\d{1,2})$').firstMatch(t);
    if (m == null) throw FormatException('Unbekannter Dart: $text');
    final mult = {'S': 1, 'D': 2, 'T': 3}[m.group(1)]!;
    return DartThrow(mult, int.parse(m.group(2)!));
  }

  bool get isMiss => multiplier == 0;
  bool get isDouble => multiplier == 2;
  bool get isTriple => multiplier == 3;
  bool get isSingle => multiplier == 1;
  bool get isBull => number == 25;

  /// Punktwert (0..60).
  int get score => multiplier * number;

  /// Kurzschreibweise für Anzeige und Persistenz (`T20`, `D16`, `S5`, `25`, `Bull`, `Miss`).
  String get label {
    if (isMiss) return 'Miss';
    if (isBull) return multiplier == 2 ? 'Bull' : '25';
    const p = {1: 'S', 2: 'D', 3: 'T'};
    return '${p[multiplier]}$number';
  }

  /// Kompakte Persistenzform als Zahl `multiplier * 100 + number`
  /// (Miss = 0, T20 = 320, Bull = 225). Bewusst kein verschachteltes Array,
  /// da Cloud Firestore keine Arrays in Arrays erlaubt.
  int toJson() => multiplier * 100 + number;

  factory DartThrow.fromJson(dynamic json) {
    final code = (json as num).toInt();
    return DartThrow(code ~/ 100, code % 100);
  }

  /// Alle gültigen Treffer außer Miss (62 Stück).
  static final List<DartThrow> allScoring = _buildAll();

  static List<DartThrow> _buildAll() {
    final out = <DartThrow>[];
    for (var n = 1; n <= 20; n++) {
      out..add(DartThrow._(1, n))..add(DartThrow._(2, n))..add(DartThrow._(3, n));
    }
    out..add(outerBull)..add(bullseye);
    return List.unmodifiable(out);
  }

  @override
  bool operator ==(Object other) =>
      other is DartThrow && other.multiplier == multiplier && other.number == number;

  @override
  int get hashCode => multiplier * 100 + number;

  @override
  String toString() => label;
}
