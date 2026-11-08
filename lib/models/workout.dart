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
    this.imported = false,
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

  /// true = veio de arquivo (GPX/TCX/FIT) e é guardado pelo app; false = Health Connect.
  final bool imported;

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

  /// Mesmo treino visto por duas fontes (ex.: importado e já no Health Connect):
  /// mesmo tipo e início com até 3 min de diferença, ou mais de 80% de sobreposição.
  bool sameSessionAs(Workout o) {
    if (o.kind != kind) return false;
    if (start.difference(o.start).inSeconds.abs() <= 180) return true;
    final a = start.isAfter(o.start) ? start : o.start;
    final b = end.isBefore(o.end) ? end : o.end;
    if (!b.isAfter(a)) return false;
    final shorter = duration < o.duration ? duration : o.duration;
    return shorter.inSeconds > 0 && b.difference(a).inSeconds / shorter.inSeconds > 0.8;
  }

  /// Serialização completa (treinos importados ficam no aparelho e na nuvem).
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'source': source,
        'distanceM': distanceM,
        'kcal': kcal,
        'steps': steps,
        'hr': [for (final h in hr) [h.time.millisecondsSinceEpoch, h.bpm]],
        'splits': splits.map((e) => e.toJson()).toList(),
        'route': route.map((e) => e.toJson()).toList(),
        'imported': imported,
      };

  factory Workout.fromJson(Map<String, dynamic> j) => Workout(
        id: j['id'] as String,
        kind: WorkoutKind.fromName(j['kind'] as String),
        title: j['title'] as String,
        start: DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
        source: j['source'] as String,
        distanceM: (j['distanceM'] as num?)?.toDouble(),
        kcal: (j['kcal'] as num?)?.toInt(),
        steps: (j['steps'] as num?)?.toInt(),
        hr: [
          for (final h in (j['hr'] as List? ?? const []))
            HrSample(DateTime.fromMillisecondsSinceEpoch((h as List)[0] as int), (h[1] as num).toDouble()),
        ],
        splits: [for (final s in (j['splits'] as List? ?? const [])) Split.fromJson(Map<String, dynamic>.from(s as Map))],
        route: [for (final r in (j['route'] as List? ?? const [])) RoutePoint.fromJson(r as List)],
        imported: j['imported'] as bool? ?? false,
      );

  Workout copyAsImported({String? source}) => Workout(
        id: id,
        kind: kind,
        title: title,
        start: start,
        end: end,
        source: source ?? this.source,
        distanceM: distanceM,
        kcal: kcal,
        steps: steps,
        hr: hr,
        splits: splits,
        route: route,
        imported: true,
      );
}
