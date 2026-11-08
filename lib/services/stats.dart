import '../models/workout.dart';

class Bucket {
  Bucket(this.label, this.start);
  final String label;
  final DateTime start;
  double km = 0;
  int count = 0;
  Duration time = Duration.zero;
}

class Records {
  const Records({this.best5k, this.best10k, this.longestKm});
  final Duration? best5k;
  final Duration? best10k;
  final double? longestKm;
}

/// Agregações para a tela de estatísticas.
class Stats {
  Stats(this.workouts, {DateTime? now}) : now = now ?? DateTime.now();
  final List<Workout> workouts;
  final DateTime now;

  Iterable<Workout> get runs => workouts.where((w) => w.kind == WorkoutKind.corrida);

  static DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  /// Km de corrida por semana (as [n] últimas, a atual por último).
  List<Bucket> weeks(int n) {
    final cur = mondayOf(now);
    final list = [for (var i = n - 1; i >= 0; i--) Bucket(i == 0 ? 'Atual' : 'S-$i', cur.subtract(Duration(days: 7 * i)))];
    for (final w in runs) {
      final m = mondayOf(w.start);
      for (final b in list) {
        if (b.start == m) {
          b.km += w.distanceKm ?? 0;
          b.count++;
          b.time += w.duration;
        }
      }
    }
    return list;
  }

  /// Km de corrida por mês (os [n] últimos).
  List<Bucket> months(int n) {
    const names = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
    final list = <Bucket>[];
    for (var i = n - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i);
      list.add(Bucket(names[d.month - 1], d));
    }
    for (final w in runs) {
      for (final b in list) {
        if (w.start.year == b.start.year && w.start.month == b.start.month) {
          b.km += w.distanceKm ?? 0;
          b.count++;
          b.time += w.duration;
        }
      }
    }
    return list;
  }

  /// Totais de um período [from, to) para todos os tipos.
  ({int count, int runs, double runKm, Duration active, double? avgPace}) totals(DateTime from, DateTime to) {
    final inRange = workouts.where((w) => !w.start.isBefore(from) && w.start.isBefore(to)).toList();
    final r = inRange.where((w) => w.kind == WorkoutKind.corrida && w.distanceKm != null).toList();
    final km = r.fold<double>(0, (s, w) => s + w.distanceKm!);
    final secs = r.fold<int>(0, (s, w) => s + w.duration.inSeconds);
    return (
      count: inRange.length,
      runs: r.length,
      runKm: km,
      active: inRange.fold(Duration.zero, (s, w) => s + w.duration),
      avgPace: km > 0 ? secs / km : null,
    );
  }

  /// Tempo ativo por tipo no período.
  Map<WorkoutKind, Duration> byKind(DateTime from, DateTime to) {
    final m = <WorkoutKind, Duration>{};
    for (final w in workouts.where((w) => !w.start.isBefore(from) && w.start.isBefore(to))) {
      m[w.kind] = (m[w.kind] ?? Duration.zero) + w.duration;
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }

  /// Recordes: melhor tempo projetado para 5 e 10 km a partir de corridas de
  /// pelo menos essa distância (pace médio × distância) e a maior corrida.
  Records records() {
    Duration? best(double d) {
      Duration? b;
      for (final w in runs) {
        final km = w.distanceKm;
        if (km == null || km < d) continue;
        final t = Duration(seconds: (w.duration.inSeconds / km * d).round());
        if (b == null || t < b) b = t;
      }
      return b;
    }

    final longest = runs.map((w) => w.distanceKm ?? 0).fold<double>(0, (a, b) => a > b ? a : b);
    return Records(best5k: best(5), best10k: best(10), longestKm: longest > 0 ? longest : null);
  }
}
