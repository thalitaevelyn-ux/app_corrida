import '../models/plan.dart';
import '../models/workout.dart';
import '../utils/format.dart';

enum SessionStatus { done, missed, today, upcoming }

class SessionProgress {
  const SessionProgress(this.session, this.date, this.status, this.workout);
  final PlanSession session;
  final DateTime date;
  final SessionStatus status;

  /// Treino do Health Connect que cumpriu esta sessão, se houver.
  final Workout? workout;
}

/// Liga as sessões do plano aos treinos registrados.
class PlanProgress {
  const PlanProgress(this.plan, this.workouts);
  final TrainingPlan plan;
  final List<Workout> workouts;

  List<SessionProgress> week(int n, {DateTime? now}) {
    now ??= DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final w = plan.week(n);
    if (w == null) return const [];
    final used = <String>{};
    return [
      for (final s in w.sessions)
        () {
          final date = plan.dateOf(n, s.weekday);
          final match = _match(s, date, used);
          if (match != null) used.add(match.id);
          final SessionStatus st;
          if (match != null || s.type == SessionType.descanso && date.isBefore(today)) {
            st = SessionStatus.done;
          } else if (date == today) {
            st = SessionStatus.today;
          } else if (date.isBefore(today)) {
            st = SessionStatus.missed;
          } else {
            st = SessionStatus.upcoming;
          }
          return SessionProgress(s, date, st, match);
        }(),
    ];
  }

  /// Próxima sessão a fazer (hoje ou futura) a partir de hoje.
  SessionProgress? next({DateTime? now}) {
    now ??= DateTime.now();
    final cur = plan.currentWeek(now);
    for (var n = cur; n <= plan.totalWeeks; n++) {
      for (final p in week(n, now: now)) {
        if (p.status == SessionStatus.today || p.status == SessionStatus.upcoming) {
          if (p.session.type != SessionType.descanso) return p;
        }
      }
    }
    return null;
  }

  Workout? _match(PlanSession s, DateTime date, Set<String> used) {
    if (s.type == SessionType.descanso) return null;
    final kinds = s.type == SessionType.forca
        ? {WorkoutKind.academia, WorkoutKind.outro}
        : s.type == SessionType.caminhadaCorrida
            ? {WorkoutKind.corrida, WorkoutKind.caminhada}
            : {WorkoutKind.corrida};
    // Aceita o treino no próprio dia ou no dia seguinte (quem troca o dia não
    // deve ficar com "perdido").
    for (final w in workouts) {
      if (used.contains(w.id) || !kinds.contains(w.kind)) continue;
      final d = DateTime(w.start.year, w.start.month, w.start.day);
      final delta = d.difference(date).inDays;
      if (delta == 0 || delta == 1) return w;
    }
    return null;
  }

  /// Resumo da semana para o backend de IA ajustar a próxima.
  Map<String, dynamic> weekReport(int n, {DateTime? now}) {
    final items = week(n, now: now);
    return {
      'semana': n,
      'planejado': plan.week(n)?.toJson(),
      'realizado': [
        for (final p in items)
          {
            'diaSemana': p.session.weekday,
            'tipoPlanejado': p.session.type.name,
            'status': p.status.name,
            if (p.workout != null) 'treino': p.workout!.toSummaryJson(),
          }
      ],
    };
  }
}

/// Ajuste semanal por regras (usado sem IA). Olha a semana que terminou e
/// mexe no volume das semanas seguintes.
class LocalAdjuster {
  const LocalAdjuster();

  TrainingPlan adjust(TrainingPlan plan, List<Workout> workouts, int finishedWeek, {String? feeling, DateTime? now}) {
    final prog = PlanProgress(plan, workouts).week(finishedWeek, now: now);
    final runs = prog.where((p) => p.session.type.isRun).toList();
    if (runs.isEmpty) return plan;
    final done = runs.where((p) => p.status == SessionStatus.done).length;
    final ratio = done / runs.length;

    double factor;
    String note;
    if (ratio < 0.5 || feeling == 'cansado') {
      factor = 0.85;
      note = ratio < 0.5
          ? 'Você completou $done de ${runs.length} corridas na semana $finishedWeek. '
              'Reduzimos o volume da próxima semana em 15% para retomar o ritmo sem risco de lesão.'
          : 'Você marcou que está cansado. A próxima semana ficou 15% mais leve.';
    } else if (ratio < 0.8) {
      factor = 1.0;
      note = 'Semana $finishedWeek: $done de ${runs.length} corridas. Mantivemos o volume da próxima semana igual ao previsto.';
    } else {
      factor = 1.0;
      note = 'Semana $finishedWeek completa ($done/${runs.length}). Plano mantido. Siga assim!';
      // Treinos leves bem mais rápidos que o previsto indicam evolução.
      final easy = prog.where((p) => p.session.type == SessionType.leve && p.workout?.paceSecPerKm != null);
      if (easy.length >= 2 && feeling != 'cansado') {
        final avg = easy.map((p) => p.workout!.paceSecPerKm!).reduce((a, b) => a + b) / easy.length;
        note = 'Semana $finishedWeek completa. Seus leves saíram em média a ${fmtPace(avg)}. '
            'Se estiver confortável, mantenha; o volume segue o plano.';
      }
    }

    if (factor == 1.0) return plan.copyWith(adjustmentNote: note, updatedAt: now ?? DateTime.now());
    final weeks = [
      for (final w in plan.weeks)
        w.number == finishedWeek + 1 ? _scale(w, factor) : w,
    ];
    return plan.copyWith(weeks: weeks, adjustmentNote: note, updatedAt: now ?? DateTime.now());
  }

  PlanWeek _scale(PlanWeek w, double f) {
    final sessions = [
      for (final s in w.sessions)
        s.distanceKm == null
            ? s
            : PlanSession(
                weekday: s.weekday,
                type: s.type,
                title: s.title.replaceAll(RegExp(r'\d+(,\d)? km'), fmtKm((s.distanceKm! * f * 2).round() / 2, decimals: 0)),
                description: s.description,
                distanceKm: (s.distanceKm! * f * 2).round() / 2,
                durationMin: s.durationMin,
                targetPace: s.targetPace,
              ),
    ];
    return PlanWeek(
      number: w.number,
      focus: w.focus,
      totalKm: sessions.fold<double>(0, (a, s) => a + (s.distanceKm ?? 0)),
      sessions: sessions,
    );
  }
}
