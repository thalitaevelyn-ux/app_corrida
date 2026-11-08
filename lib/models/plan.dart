/// Plano de treino. O formato JSON (chaves em português) é o mesmo que o
/// backend de IA devolve, então o plano da IA e o plano local se misturam.
library;

enum SessionType {
  leve('Leve'),
  regenerativo('Regenerativo'),
  longao('Longão'),
  tempo('Tempo run'),
  intervalado('Intervalado'),
  fartlek('Fartlek'),
  caminhadaCorrida('Caminhada + corrida'),
  forca('Fortalecimento'),
  descanso('Descanso');

  const SessionType(this.label);
  final String label;

  bool get isRun => this != forca && this != descanso;
  bool get isQuality => this == tempo || this == intervalado || this == fartlek;

  static SessionType fromName(String n) =>
      SessionType.values.firstWhere((t) => t.name == n, orElse: () => SessionType.leve);
}

class PlanSession {
  const PlanSession({
    required this.weekday,
    required this.type,
    required this.title,
    required this.description,
    this.distanceKm,
    this.durationMin,
    this.targetPace,
  });

  /// 1 = segunda ... 7 = domingo.
  final int weekday;
  final SessionType type;
  final String title;
  final String description;
  final double? distanceKm;
  final int? durationMin;

  /// Texto livre, ex.: "6:20–6:40 /km".
  final String? targetPace;

  Map<String, dynamic> toJson() => {
        'diaSemana': weekday,
        'tipo': type.name,
        'titulo': title,
        'descricao': description,
        'distanciaKm': distanceKm,
        'duracaoMin': durationMin,
        'paceAlvo': targetPace,
      };

  factory PlanSession.fromJson(Map<String, dynamic> j) => PlanSession(
        weekday: (j['diaSemana'] as num).toInt().clamp(1, 7),
        type: SessionType.fromName(j['tipo'] as String),
        title: j['titulo'] as String,
        description: (j['descricao'] as String?) ?? '',
        distanceKm: (j['distanciaKm'] as num?)?.toDouble(),
        durationMin: (j['duracaoMin'] as num?)?.toInt(),
        targetPace: j['paceAlvo'] as String?,
      );
}

class PlanWeek {
  const PlanWeek({required this.number, required this.focus, required this.totalKm, required this.sessions});

  final int number;
  final String focus;
  final double totalKm;
  final List<PlanSession> sessions;

  Map<String, dynamic> toJson() => {
        'numero': number,
        'foco': focus,
        'kmTotal': totalKm,
        'treinos': sessions.map((s) => s.toJson()).toList(),
      };

  factory PlanWeek.fromJson(Map<String, dynamic> j) {
    final sessions = (j['treinos'] as List).map((e) => PlanSession.fromJson(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.weekday.compareTo(b.weekday));
    return PlanWeek(
      number: (j['numero'] as num).toInt(),
      focus: (j['foco'] as String?) ?? '',
      totalKm: (j['kmTotal'] as num?)?.toDouble() ?? 0,
      sessions: sessions,
    );
  }
}

class Paces {
  const Paces({required this.easy, required this.threshold, required this.interval, required this.long});
  final String easy;
  final String threshold;
  final String interval;
  final String long;

  Map<String, dynamic> toJson() => {'leve': easy, 'limiar': threshold, 'intervalo': interval, 'longao': long};

  factory Paces.fromJson(Map<String, dynamic> j) => Paces(
        easy: j['leve'] as String,
        threshold: j['limiar'] as String,
        interval: j['intervalo'] as String,
        long: j['longao'] as String,
      );
}

class TrainingPlan {
  TrainingPlan({
    required this.startDate,
    required this.summary,
    required this.estimatedLevel,
    required this.paces,
    required this.weeks,
    required this.source,
    required this.updatedAt,
    this.adjustmentNote,
  });

  /// Segunda-feira da semana 1.
  final DateTime startDate;
  final String summary;
  final String estimatedLevel;
  final Paces paces;
  final List<PlanWeek> weeks;

  /// "ia" ou "local".
  final String source;
  final DateTime updatedAt;

  /// Explicação do último ajuste semanal, mostrada na tela inicial.
  final String? adjustmentNote;

  int get totalWeeks => weeks.length;

  /// Semana atual (1-based), limitada ao intervalo do plano.
  int currentWeek(DateTime now) {
    final days = DateTime(now.year, now.month, now.day).difference(startDate).inDays;
    return (days ~/ 7 + 1).clamp(1, weeks.isEmpty ? 1 : weeks.length);
  }

  DateTime dateOf(int week, int weekday) => startDate.add(Duration(days: (week - 1) * 7 + weekday - 1));

  PlanWeek? week(int n) => n >= 1 && n <= weeks.length ? weeks[n - 1] : null;

  TrainingPlan copyWith({List<PlanWeek>? weeks, Paces? paces, String? adjustmentNote, String? source, DateTime? updatedAt}) =>
      TrainingPlan(
        startDate: startDate,
        summary: summary,
        estimatedLevel: estimatedLevel,
        paces: paces ?? this.paces,
        weeks: weeks ?? this.weeks,
        source: source ?? this.source,
        updatedAt: updatedAt ?? this.updatedAt,
        adjustmentNote: adjustmentNote ?? this.adjustmentNote,
      );

  Map<String, dynamic> toJson() => {
        'inicio': startDate.toIso8601String(),
        'resumo': summary,
        'nivelEstimado': estimatedLevel,
        'paces': paces.toJson(),
        'semanas': weeks.map((w) => w.toJson()).toList(),
        'origem': source,
        'atualizadoEm': updatedAt.toIso8601String(),
        if (adjustmentNote != null) 'notaAjuste': adjustmentNote,
      };

  factory TrainingPlan.fromJson(Map<String, dynamic> j) => TrainingPlan(
        startDate: DateTime.parse(j['inicio'] as String),
        summary: j['resumo'] as String,
        estimatedLevel: (j['nivelEstimado'] as String?) ?? '',
        paces: Paces.fromJson(j['paces'] as Map<String, dynamic>),
        weeks: (j['semanas'] as List).map((e) => PlanWeek.fromJson(e as Map<String, dynamic>)).toList(),
        source: (j['origem'] as String?) ?? 'local',
        updatedAt: DateTime.parse(j['atualizadoEm'] as String),
        adjustmentNote: j['notaAjuste'] as String?,
      );
}
