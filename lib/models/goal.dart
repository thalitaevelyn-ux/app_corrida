enum GoalType {
  distancia('Completar uma distância', '5 km, 10 km, meia ou maratona'),
  tempo('Melhorar meu tempo', 'Bater um tempo-alvo numa distância'),
  base('Construir base', 'Correr com regularidade e mais volume'),
  sofa5k('Do sofá aos 5 km', 'Caminhada e corrida intercaladas');

  const GoalType(this.title, this.description);
  final String title;
  final String description;

  static GoalType fromName(String n) => GoalType.values.firstWhere((g) => g.name == n, orElse: () => GoalType.distancia);
}

/// Objetivo e perfil básico do usuário.
class Goal {
  const Goal({
    required this.type,
    required this.distanceKm,
    required this.daysPerWeek,
    this.targetTime,
    this.raceDate,
    this.age,
    this.weightKg,
  });

  final GoalType type;

  /// Distância-alvo (para `base`, é o volume semanal desejado em km).
  final double distanceKm;
  final int daysPerWeek;
  final Duration? targetTime;
  final DateTime? raceDate;
  final int? age;
  final double? weightKg;

  /// FC máxima estimada (fórmula de Tanaka) usada nas zonas.
  int get maxHr => age == null ? 190 : (208 - 0.7 * age!).round();

  String get shortTitle {
    final d = _fmtKm(distanceKm);
    switch (type) {
      case GoalType.distancia:
        return 'Completar $d';
      case GoalType.tempo:
        return targetTime == null ? 'Melhorar $d' : '$d em ${_fmtDur(targetTime!)}';
      case GoalType.base:
        return 'Base: $d/semana';
      case GoalType.sofa5k:
        return 'Primeiros 5 km';
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'distanceKm': distanceKm,
        'daysPerWeek': daysPerWeek,
        if (targetTime != null) 'targetSec': targetTime!.inSeconds,
        if (raceDate != null) 'raceDate': raceDate!.toIso8601String(),
        if (age != null) 'age': age,
        if (weightKg != null) 'weightKg': weightKg,
      };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        type: GoalType.fromName(j['type'] as String),
        distanceKm: (j['distanceKm'] as num).toDouble(),
        daysPerWeek: j['daysPerWeek'] as int,
        targetTime: j['targetSec'] == null ? null : Duration(seconds: j['targetSec'] as int),
        raceDate: j['raceDate'] == null ? null : DateTime.parse(j['raceDate'] as String),
        age: j['age'] as int?,
        weightKg: (j['weightKg'] as num?)?.toDouble(),
      );

  /// Formato enviado ao backend de IA.
  Map<String, dynamic> toApiJson() => {
        'tipo': type.name,
        'distanciaKm': distanceKm,
        'diasPorSemana': daysPerWeek,
        if (targetTime != null) 'tempoAlvoSeg': targetTime!.inSeconds,
        if (raceDate != null) 'dataProva': raceDate!.toIso8601String().substring(0, 10),
        if (age != null) 'idade': age,
        if (weightKg != null) 'pesoKg': weightKg,
      };
}

String _fmtKm(double km) {
  if (km == 21.1 || km == 21.0975) return 'meia maratona';
  if (km == 42.2 || km == 42.195) return 'maratona';
  final s = km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toStringAsFixed(1).replaceAll('.', ',');
  return '$s km';
}

String _fmtDur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}
