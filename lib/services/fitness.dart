import 'dart:math' as math;

import '../models/workout.dart';
import '../utils/format.dart';

/// Nível estimado a partir do histórico do Health Connect.
class FitnessProfile {
  const FitnessProfile({
    required this.weeklyKm,
    required this.runsPerWeek,
    required this.est5kSec,
    required this.longestRunKm,
    required this.runCount,
  });

  /// Média de km de corrida por semana nas últimas 8 semanas.
  final double weeklyKm;
  final double runsPerWeek;

  /// Tempo estimado para 5 km, em segundos.
  final double est5kSec;
  final double longestRunKm;
  final int runCount;

  bool get isBeginner => runCount < 4 || weeklyKm < 5;

  double get pace5k => est5kSec / 5;

  /// Paces de treino derivados do 5 km (aproximação das zonas de Daniels).
  double get easyPace => pace5k * 1.22;
  double get longPace => pace5k * 1.25;
  double get thresholdPace => pace5k * 1.06;
  double get intervalPace => pace5k * 0.98;

  String get levelLabel {
    if (runCount == 0) return 'Iniciante (sem corridas registradas)';
    if (isBeginner) return 'Iniciante';
    if (est5kSec < 22 * 60) return 'Avançado';
    if (est5kSec < 28 * 60) return 'Intermediário';
    return 'Iniciante em evolução';
  }

  String describe() {
    if (runCount == 0) return 'Nenhuma corrida nos últimos 90 dias.';
    return '$runCount corridas nos últimos 90 dias · média ${fmtKm(weeklyKm)}/semana · '
        '5 km estimado em ${fmtDuration(Duration(seconds: est5kSec.round()))}';
  }

  Map<String, dynamic> toApiJson() => {
        'kmSemanaMedia': double.parse(weeklyKm.toStringAsFixed(1)),
        'corridasPorSemana': double.parse(runsPerWeek.toStringAsFixed(1)),
        'tempo5kEstimadoSeg': est5kSec.round(),
        'maiorCorridaKm': double.parse(longestRunKm.toStringAsFixed(1)),
        'corridas90d': runCount,
      };
}

/// Fórmula de Riegel: prevê o tempo em d2 a partir de um tempo em d1.
double riegel(double t1Sec, double d1Km, double d2Km) => t1Sec * math.pow(d2Km / d1Km, 1.06);

FitnessProfile estimateFitness(List<Workout> workouts, {DateTime? now}) {
  now ??= DateTime.now();
  final runs = workouts
      .where((w) => w.kind == WorkoutKind.corrida && (w.distanceKm ?? 0) >= 1 && now!.difference(w.start).inDays <= 90)
      .toList();

  if (runs.isEmpty) {
    // Iniciante sem histórico: 5 km em ~40 min (8:00 /km) como referência.
    return const FitnessProfile(weeklyKm: 0, runsPerWeek: 0, est5kSec: 40 * 60, longestRunKm: 0, runCount: 0);
  }

  final recent = runs.where((w) => now!.difference(w.start).inDays <= 56).toList();
  final km8w = recent.fold<double>(0, (s, w) => s + w.distanceKm!);

  // Melhor previsão de 5 km entre corridas de 3 km ou mais. Corridas de treino
  // costumam ser mais lentas que esforço de prova, então aplicamos 3% de desconto.
  double best = double.infinity;
  for (final w in runs.where((w) => w.distanceKm! >= 3)) {
    final p = riegel(w.duration.inSeconds.toDouble(), w.distanceKm!, 5) * 0.97;
    if (p < best) best = p;
  }
  if (best == double.infinity) {
    final w = runs.reduce((a, b) => (a.paceSecPerKm ?? 9e9) < (b.paceSecPerKm ?? 9e9) ? a : b);
    best = riegel(w.duration.inSeconds.toDouble(), w.distanceKm!, 5);
  }
  // Limites de sanidade (GPS ruim pode gerar paces impossíveis).
  best = best.clamp(15 * 60.0, 55 * 60.0);

  return FitnessProfile(
    weeklyKm: km8w / 8,
    runsPerWeek: recent.length / 8,
    est5kSec: best,
    longestRunKm: runs.map((w) => w.distanceKm!).reduce(math.max),
    runCount: runs.length,
  );
}
