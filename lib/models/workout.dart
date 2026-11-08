/// Tipos de treino que o app reconhece. Os tipos do Health Connect são
/// agrupados nestas categorias para filtros e estatísticas.
enum WorkoutKind {
  corrida('Corrida'),
  caminhada('Caminhada'),
  bike('Bike'),
  academia('Academia'),
  outro('Outro');

  const WorkoutKind(this.label);
  final String label;

  static WorkoutKind fromName(String name) =>
      WorkoutKind.values.firstWhere((k) => k.name == name, orElse: () => WorkoutKind.outro);
}

class HrSample {
  const HrSample(this.time, this.bpm);
  final DateTime time;
  final double bpm;
}

/// Parcial de 1 km (só existe para corridas gravadas por este app).
class Split {
  const Split({required this.km, required this.duration, this.avgHr});
  final int km;
  final Duration duration;
  final double? avgHr;

  Map<String, dynamic> toJson() => {'km': km, 'ms': duration.inMilliseconds, if (avgHr != null) 'hr': avgHr};

  factory Split.fromJson(Map<String, dynamic> j) => Split(
        km: j['km'] as int,
        duration: Duration(milliseconds: j['ms'] as int),
        avgHr: (j['hr'] as num?)?.toDouble(),
      );
}

class RoutePoint {
  const RoutePoint(this.lat, this.lng);
  final double lat;
  final double lng;

  List<double> toJson() => [lat, lng];
  factory RoutePoint.fromJson(List<dynamic> j) =>
      RoutePoint((j[0] as num).toDouble(), (j[1] as num).toDouble());
}

class Workout {
  Workout({
    required this.id,
    required this.kind,
    required this.title,
    required this.start,
    required this.end,
    required this.source,
    this.distanceM,
    this.kcal,
    this.steps,
    this.hr = const [],
    this.splits = const [],
    this.route = const [],
  });

  final String id;
  final WorkoutKind kind;
  final String title;
  final DateTime start;
  final DateTime end;

  /// App de origem (ex.: "Samsung Health", "Strava", "Fast run").
  final String source;
  final double? distanceM;
  final int? kcal;
  final int? steps;

  /// Carregados sob demanda na tela de detalhe.
  List<HrSample> hr;
  List<Split> splits;
  List<RoutePoint> route;

  Duration get duration => end.difference(start);

  double? get distanceKm => (distanceM == null || distanceM! <= 0) ? null : distanceM! / 1000;

  /// Pace em segundos por km (só faz sentido para corrida e caminhada).
  double? get paceSecPerKm {
    final km = distanceKm;
    if (km == null || km < 0.05) return null;
    return duration.inSeconds / km;
  }

  double? get speedKmh {
    final km = distanceKm;
    if (km == null || duration.inSeconds == 0) return null;
    return km / (duration.inSeconds / 3600);
  }

  double? get avgHr {
    if (hr.isEmpty) return null;
    return hr.map((s) => s.bpm).reduce((a, b) => a + b) / hr.length;
  }

  /// Resumo compacto enviado ao backend de IA (sem dados de localização).
  Map<String, dynamic> toSummaryJson() => {
        'data': start.toIso8601String(),
        'tipo': kind.name,
        'duracaoMin': (duration.inSeconds / 60).round(),
        if (distanceKm != null) 'distanciaKm': double.parse(distanceKm!.toStringAsFixed(2)),
        if (paceSecPerKm != null && (kind == WorkoutKind.corrida || kind == WorkoutKind.caminhada))
          'paceSegKm': paceSecPerKm!.round(),
        if (avgHr != null) 'fcMedia': avgHr!.round(),
      };
}
