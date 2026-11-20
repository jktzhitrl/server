/// Teilnehmer eines Turniers.
class Participant {
  final String id;
  final String name;

  /// Setzplatz (1 = bester). `null` = ungesetzt.
  final int? seed;

  const Participant({required this.id, required this.name, this.seed});

  Participant copyWith({String? name, int? seed, bool clearSeed = false}) => Participant(
        id: id,
        name: name ?? this.name,
        seed: clearSeed ? null : (seed ?? this.seed),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'seed': seed};

  factory Participant.fromJson(Map<String, dynamic> j) => Participant(
        id: j['id'] as String,
        name: j['name'] as String,
        seed: (j['seed'] as num?)?.toInt(),
      );

  @override
  String toString() => name;
}
