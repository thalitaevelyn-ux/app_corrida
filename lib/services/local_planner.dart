import 'dart:math' as math;

import '../models/goal.dart';
import '../models/plan.dart';
import '../utils/format.dart';
import 'fitness.dart';

/// Gerador de plano por regras. É usado quando o backend de IA não está
/// configurado ou falha, para o app nunca ficar sem plano.
///
/// Princípios: volume sobe no máximo ~10% por semana, semana de recuperação a
/// cada 4, polimento nas 1–2 semanas finais, ~20% do volume em intensidade.
class LocalPlanner {
  const LocalPlanner();

  TrainingPlan generate(Goal goal, FitnessProfile fit, {DateTime? now}) {
    now ??= DateTime.now();
    final start = _nextMonday(now);
    if (goal.type == GoalType.sofa5k) return _couchTo5k(goal, fit, start, now);

    final nWeeks = _weeksFor(goal, start);
    final days = goal.daysPerWeek.clamp(3, 6);
    final peak = _peakKm(goal, days);
    final startKm = math.max(fit.isBeginner ? 8.0 : fit.weeklyKm, days * 3.0).clamp(6.0, peak).toDouble();

    final weeks = <PlanWeek>[];
    var km = startKm;
    for (var w = 1; w <= nWeeks; w++) {
      final weeksLeft = nWeeks - w;
      double weekKm;
      String focus;
      if (goal.type != GoalType.base && weeksLeft == 0) {
        weekKm = peak * 0.45;
        focus = 'Semana da prova: descanso ativo';
      } else if (goal.type != GoalType.base && weeksLeft == 1 && nWeeks >= 8) {
        weekKm = peak * 0.7;
        focus = 'Polimento: menos volume, mantém o ritmo';
      } else if (w % 4 == 0) {
        weekKm = km * 0.8;
        focus = 'Recuperação: absorver o treino';
      } else {
        if (w > 1) km = math.min(km * 1.08, peak);
        weekKm = km;
        focus = w <= 3 ? 'Base aeróbica' : (weekKm >= peak * 0.95 ? 'Pico de volume' : 'Construção');
      }
      weeks.add(_buildWeek(w, focus, weekKm, days, goal, fit, nWeeks));
    }

    final target = goal.targetTime;
    final summary = StringBuffer('${goal.shortTitle} em $nWeeks semanas, $days treinos por semana. ')
      ..write('Volume sai de ${fmtKm(startKm, decimals: 0)} e chega a ${fmtKm(peak, decimals: 0)} por semana, ')
      ..write('com recuperação a cada 4 semanas.');
    if (target != null) {
      final pred = riegel(fit.est5kSec, 5, goal.distanceKm);
      summary.write(' Previsão atual para ${fmtKm(goal.distanceKm, decimals: 1)}: '
          '${fmtDuration(Duration(seconds: pred.round()))}; meta ${fmtDuration(target)}.');
    }

    return TrainingPlan(
      startDate: start,
      summary: summary.toString(),
      estimatedLevel: fit.levelLabel,
      paces: _paces(fit, goal),
      weeks: weeks,
      source: 'local',
      updatedAt: now,
    );
  }

  PlanWeek _buildWeek(int n, String focus, double km, int days, Goal goal, FitnessProfile fit, int nWeeks) {
    final p = _paces(fit, goal);
    final slots = _slots[days]!;
    final sessions = <PlanSession>[];
    final longKm = _round(km * (days <= 3 ? 0.4 : 0.32));
    final qualityAllowed = (n >= 3 && !fit.isBeginner) || n >= 5;
    final isRace = goal.type != GoalType.base && n == nWeeks;

    var remaining = km - longKm;
    final others = slots.length - 1;
    for (var i = 0; i < slots.length; i++) {
      final wd = slots[i];
      if (i == slots.length - 1) {
        if (isRace) {
          sessions.add(PlanSession(
            weekday: wd,
            type: SessionType.longao,
            title: 'Dia da prova: ${fmtKm(goal.distanceKm, decimals: 1)}',
            description: goal.targetTime == null
                ? 'Comece devagar e termine forte.'
                : 'Ritmo-alvo ${fmtPace(goal.targetTime!.inSeconds / goal.distanceKm)}. Comece 5 s/km mais lento.',
            distanceKm: goal.distanceKm,
            targetPace: goal.targetTime == null ? p.long : fmtPace(goal.targetTime!.inSeconds / goal.distanceKm),
          ));
        } else {
          sessions.add(PlanSession(
            weekday: wd,
            type: SessionType.longao,
            title: 'Longão ${fmtKm(longKm, decimals: 0)}',
            description: 'Ritmo confortável, dá para conversar. Hidrate-se.',
            distanceKm: longKm,
            targetPace: p.long,
          ));
        }
        continue;
      }
      final easyKm = _round(remaining / (others - i));
      // A primeira sessão do meio da semana vira treino de qualidade.
      if (qualityAllowed && i == 1 && goal.type != GoalType.base && !isRace) {
        final quality = n.isEven ? _intervals(n, fit, wd) : _tempo(n, fit, wd);
        sessions.add(quality);
        remaining -= quality.distanceKm ?? easyKm;
      } else if (days >= 5 && i == 0) {
        sessions.add(PlanSession(
          weekday: wd,
          type: SessionType.regenerativo,
          title: 'Regenerativo ${fmtKm(math.max(3, easyKm * 0.7), decimals: 0)}',
          description: 'Bem leve, para soltar as pernas.',
          distanceKm: _round(math.max(3, easyKm * 0.7)),
          targetPace: fmtPace(fit.easyPace + 20),
        ));
        remaining -= math.max(3, easyKm * 0.7);
      } else {
        sessions.add(PlanSession(
          weekday: wd,
          type: SessionType.leve,
          title: 'Leve ${fmtKm(easyKm, decimals: 0)}',
          description: 'Zona 2: respiração controlada.',
          distanceKm: easyKm,
          targetPace: p.easy,
        ));
        remaining -= easyKm;
      }
    }
    if (days <= 4 && !isRace) {
      // Fortalecimento num dia livre ajuda a prevenir lesões.
      final free = List.generate(7, (i) => i + 1).firstWhere((d) => !slots.contains(d), orElse: () => 0);
      if (free != 0) {
        sessions.add(PlanSession(
          weekday: free,
          type: SessionType.forca,
          title: 'Fortalecimento 30 min',
          description: 'Agachamento, afundo, panturrilha, prancha. 3 séries de 12.',
          durationMin: 30,
        ));
      }
    }
    sessions.sort((a, b) => a.weekday.compareTo(b.weekday));
    final total = sessions.fold<double>(0, (s, e) => s + (e.distanceKm ?? 0));
    return PlanWeek(number: n, focus: focus, totalKm: _round(total), sessions: sessions);
  }

  PlanSession _intervals(int week, FitnessProfile fit, int weekday) {
    final reps = (4 + week ~/ 2).clamp(4, 8);
    final dist = week < 6 ? 400 : 800;
    final km = _round(3 + reps * dist / 1000 * 1.6);
    return PlanSession(
      weekday: weekday,
      type: SessionType.intervalado,
      title: 'Intervalado $reps × $dist m',
      description: 'Aquecimento 10 min leve · $reps × $dist m a ${fmtPace(fit.intervalPace)} · '
          '${dist == 400 ? '90 s' : '2 min'} de trote entre · desaquecimento 8 min.',
      distanceKm: km,
      targetPace: fmtPace(fit.intervalPace),
    );
  }

  PlanSession _tempo(int week, FitnessProfile fit, int weekday) {
    final blockKm = (2 + week ~/ 3).clamp(2, 6);
    final km = _round(blockKm + 3.0);
    return PlanSession(
      weekday: weekday,
      type: SessionType.tempo,
      title: 'Tempo run $blockKm km',
      description: '1,5 km leve · $blockKm km a ${fmtPace(fit.thresholdPace)} (forte mas sustentável) · 1,5 km leve.',
      distanceKm: km,
      targetPace: fmtPace(fit.thresholdPace),
    );
  }

  /// Programa de 8 semanas de caminhada/corrida, 3 dias por semana.
  TrainingPlan _couchTo5k(Goal goal, FitnessProfile fit, DateTime start, DateTime now) {
    const blocks = [
      ('1 min correndo / 1,5 min andando × 8', 20),
      ('1,5 min correndo / 2 min andando × 6', 21),
      ('2 min correndo / 2 min andando × 6', 24),
      ('3 min correndo / 1,5 min andando × 5', 23),
      ('5 min correndo / 2 min andando × 4', 28),
      ('8 min correndo / 2 min andando × 3', 30),
      ('12 min correndo / 2 min andando × 2', 28),
      ('25–30 min correndo sem parar', 30),
    ];
    final slots = _slots[goal.daysPerWeek.clamp(3, 4)]!;
    final weeks = <PlanWeek>[];
    for (var i = 0; i < blocks.length; i++) {
      final (desc, min) = blocks[i];
      final sessions = [
        for (final (j, wd) in slots.indexed)
          (i == blocks.length - 1 && j == slots.length - 1)
              ? PlanSession(
                  weekday: wd,
                  type: SessionType.longao,
                  title: 'Seus primeiros 5 km',
                  description: 'Ritmo bem confortável. Se precisar, ande 1 min e volte a correr.',
                  distanceKm: 5,
                  targetPace: fmtPace(fit.easyPace + 30),
                )
              : PlanSession(
                  weekday: wd,
                  type: SessionType.caminhadaCorrida,
                  title: 'Caminhada + corrida $min min',
                  description: '5 min caminhando para aquecer · $desc · 5 min caminhando.',
                  durationMin: min + 10,
                ),
      ];
      weeks.add(PlanWeek(
        number: i + 1,
        focus: i < 3 ? 'Adaptação' : (i < 6 ? 'Mais tempo correndo' : 'Rumo aos 5 km'),
        totalKm: 0,
        sessions: sessions,
      ));
    }
    return TrainingPlan(
      startDate: start,
      summary: 'Programa de 8 semanas alternando caminhada e corrida. O tempo correndo aumenta aos poucos, '
          'até você completar 5 km. Se uma semana ficar difícil, repita-a.',
      estimatedLevel: fit.levelLabel,
      paces: _paces(fit, goal),
      weeks: weeks,
      source: 'local',
      updatedAt: now,
    );
  }

  Paces _paces(FitnessProfile fit, Goal goal) => Paces(
        easy: '${fmtPace(fit.easyPace - 8, unit: false)}–${fmtPace(fit.easyPace + 12)}',
        threshold: fmtPace(fit.thresholdPace),
        interval: fmtPace(fit.intervalPace),
        long: fmtPace(fit.longPace),
      );

  int _weeksFor(Goal goal, DateTime start) {
    if (goal.raceDate != null) {
      final w = (goal.raceDate!.difference(start).inDays / 7).ceil();
      return w.clamp(4, 24);
    }
    if (goal.type == GoalType.base) return 10;
    if (goal.distanceKm >= 40) return 18;
    if (goal.distanceKm >= 20) return 14;
    return 12;
  }

  double _peakKm(Goal goal, int days) {
    if (goal.type == GoalType.base) return goal.distanceKm;
    final d = goal.distanceKm;
    final byDist = d >= 40 ? 55.0 : d >= 20 ? 40.0 : d >= 10 ? 30.0 : 20.0;
    // Poucos dias por semana limitam o volume seguro.
    return math.min(byDist, days * (d >= 20 ? 11.0 : 8.0));
  }

  static const _slots = {
    3: [2, 4, 7],
    4: [2, 4, 6, 7],
    5: [1, 2, 4, 6, 7],
    6: [1, 2, 3, 5, 6, 7],
  };

  static double _round(double km) => (km * 2).round() / 2;

  static DateTime _nextMonday(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    // Começa nesta semana se ainda é seg/ter; senão, na próxima.
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return today.weekday <= 2 ? monday : monday.add(const Duration(days: 7));
  }
}
