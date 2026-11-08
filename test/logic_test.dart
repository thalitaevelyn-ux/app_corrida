import 'package:app_corrida/models/goal.dart';
import 'package:app_corrida/models/plan.dart';
import 'package:app_corrida/models/workout.dart';
import 'package:app_corrida/services/fitness.dart';
import 'package:app_corrida/services/local_planner.dart';
import 'package:app_corrida/services/plan_progress.dart';
import 'package:app_corrida/services/run_recorder.dart';
import 'package:app_corrida/services/stats.dart';
import 'package:app_corrida/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

Workout run(DateTime start, double km, Duration dur, {String id = '', WorkoutKind kind = WorkoutKind.corrida}) => Workout(
      id: id.isEmpty ? '${start.millisecondsSinceEpoch}' : id,
      kind: kind,
      title: 'Corrida',
      start: start,
      end: start.add(dur),
      source: 'teste',
      distanceM: km * 1000,
    );

void main() {
  // Quarta-feira, 4/11/2026 — o plano começa na segunda seguinte (9/11).
  final now = DateTime(2026, 11, 4, 8);

  group('formatação', () {
    test('pace e duração', () {
      expect(fmtPace(374), '6:14 /km');
      expect(fmtPace(null), '—');
      expect(fmtDuration(const Duration(minutes: 38, seconds: 40)), '38:40');
      expect(fmtDuration(const Duration(hours: 1, minutes: 5, seconds: 3)), '1:05:03');
      expect(parseDuration('55:00'), const Duration(minutes: 55));
      expect(parseDuration('1:59:30'), const Duration(hours: 1, minutes: 59, seconds: 30));
      expect(parseDuration('abc'), isNull);
    });
  });

  group('estimativa de nível', () {
    test('sem corridas → iniciante com referência de 40 min nos 5 km', () {
      final f = estimateFitness([], now: now);
      expect(f.runCount, 0);
      expect(f.isBeginner, isTrue);
      expect(f.est5kSec, 40 * 60);
    });

    test('histórico regular estima 5 km e volume semanal', () {
      final ws = [
        for (var i = 0; i < 16; i++) run(now.subtract(Duration(days: 3 + i * 3)), 6, const Duration(minutes: 36)),
      ];
      final f = estimateFitness(ws, now: now);
      expect(f.runCount, 16);
      expect(f.isBeginner, isFalse);
      // 6 km em 36 min (6:00/km) → 5 km previsto ~29:40, com desconto ~28:50.
      expect(f.est5kSec, inInclusiveRange(27 * 60, 30 * 60));
      expect(f.weeklyKm, closeTo(16 * 6 / 8, 0.01));
      expect(f.easyPace, greaterThan(f.pace5k));
      expect(f.intervalPace, lessThan(f.thresholdPace));
    });
  });

  group('plano local', () {
    test('objetivo de distância com prova: semanas até a data, polimento e prova', () {
      final goal = Goal(type: GoalType.distancia, distanceKm: 10, daysPerWeek: 4, raceDate: DateTime(2027, 1, 31));
      final plan = const LocalPlanner().generate(goal, estimateFitness([], now: now), now: now);
      expect(plan.startDate, DateTime(2026, 11, 9));
      expect(plan.weeks.length, 12);
      expect(plan.weeks.last.focus, contains('prova'));
      expect(plan.weeks.last.sessions.last.title, contains('Dia da prova'));
      for (final w in plan.weeks) {
        final runs = w.sessions.where((s) => s.type.isRun).length;
        expect(runs, 4, reason: 'semana ${w.number}');
        expect(w.sessions.every((s) => s.weekday >= 1 && s.weekday <= 7), isTrue);
        // Nunca dois treinos no mesmo dia.
        expect(w.sessions.map((s) => s.weekday).toSet().length, w.sessions.length);
      }
    });

    test('volume não sobe mais de ~10% por semana fora da recuperação', () {
      final ws = [for (var i = 0; i < 20; i++) run(now.subtract(Duration(days: 2 + i * 2)), 5, const Duration(minutes: 30))];
      final goal = const Goal(type: GoalType.distancia, distanceKm: 21.1, daysPerWeek: 5);
      final plan = const LocalPlanner().generate(goal, estimateFitness(ws, now: now), now: now);
      // Compara com a última semana que não foi de recuperação (a cada 4).
      for (var i = 1; i < plan.weeks.length - 2; i++) {
        if ((i + 1) % 4 == 0) continue;
        final ref = (i % 4 == 0 && i >= 2) ? plan.weeks[i - 2] : plan.weeks[i - 1];
        final prev = ref.totalKm, cur = plan.weeks[i].totalKm;
        // Tolerância extra pelo arredondamento de 0,5 km por sessão.
        if (prev > 0) expect(cur / prev, lessThanOrEqualTo(1.2), reason: 'semana ${i + 1}: $prev → $cur');
      }
      // Semana 4 é de recuperação: menos volume que a 3.
      expect(plan.weeks[3].totalKm, lessThan(plan.weeks[2].totalKm));
      expect(plan.weeks.expand((w) => w.sessions).any((s) => s.type.isQuality), isTrue);
    });

    test('do sofá aos 5 km: 8 semanas de caminhada/corrida terminando nos 5 km', () {
      final plan = const LocalPlanner()
          .generate(const Goal(type: GoalType.sofa5k, distanceKm: 5, daysPerWeek: 3), estimateFitness([], now: now), now: now);
      expect(plan.weeks.length, 8);
      expect(plan.weeks.first.sessions.every((s) => s.type == SessionType.caminhadaCorrida), isTrue);
      expect(plan.weeks.last.sessions.last.distanceKm, 5);
    });

    test('plano sobrevive a ida e volta em JSON', () {
      final plan = const LocalPlanner()
          .generate(const Goal(type: GoalType.base, distanceKm: 30, daysPerWeek: 4), estimateFitness([], now: now), now: now);
      final back = TrainingPlan.fromJson(plan.toJson());
      expect(back.weeks.length, plan.weeks.length);
      expect(back.weeks[2].sessions.first.title, plan.weeks[2].sessions.first.title);
      expect(back.paces.easy, plan.paces.easy);
    });
  });

  group('aderência e ajuste semanal', () {
    final goal = const Goal(type: GoalType.distancia, distanceKm: 10, daysPerWeek: 3);
    late TrainingPlan plan;
    setUp(() => plan = const LocalPlanner().generate(goal, estimateFitness([], now: now), now: now));

    test('treino no dia (ou no seguinte) conta como feito; o resto vira perdido', () {
      final w1 = plan.week(1)!;
      final first = w1.sessions.firstWhere((s) => s.type.isRun);
      final done = run(plan.dateOf(1, first.weekday).add(const Duration(hours: 7)), 5, const Duration(minutes: 35));
      final after = plan.dateOf(2, 1).add(const Duration(hours: 9)); // segunda da semana 2
      final prog = PlanProgress(plan, [done]).week(1, now: after);
      final runs = prog.where((p) => p.session.type.isRun).toList();
      expect(runs.where((p) => p.status == SessionStatus.done).length, 1);
      expect(runs.where((p) => p.status == SessionStatus.missed).length, runs.length - 1);
    });

    test('semana fraca reduz o volume da seguinte', () {
      final after = plan.dateOf(2, 1).add(const Duration(hours: 9));
      final adjusted = const LocalAdjuster().adjust(plan, [], 1, now: after);
      expect(adjusted.week(2)!.totalKm, lessThan(plan.week(2)!.totalKm));
      expect(adjusted.adjustmentNote, contains('Reduzimos'));
      expect(adjusted.week(3)!.totalKm, plan.week(3)!.totalKm);
    });

    test('semana completa mantém o plano', () {
      final ws = [
        for (final s in plan.week(1)!.sessions.where((s) => s.type.isRun))
          run(plan.dateOf(1, s.weekday).add(const Duration(hours: 7)), s.distanceKm ?? 5, const Duration(minutes: 35)),
      ];
      final after = plan.dateOf(2, 1).add(const Duration(hours: 9));
      final adjusted = const LocalAdjuster().adjust(plan, ws, 1, now: after);
      expect(adjusted.week(2)!.totalKm, plan.week(2)!.totalKm);
      expect(adjusted.adjustmentNote, contains('completa'));
    });
  });

  group('gravação (RunTracker)', () {
    test('soma distância, ignora ruído e fecha parciais', () {
      final t0 = DateTime(2026, 11, 8, 7);
      final tr = RunTracker()..start(t0);
      // ~3 m/s para o norte: 0,00003° de latitude ≈ 3,3 m por segundo.
      for (var i = 0; i <= 400; i++) {
        tr.add(Fix(lat: -23.55 + i * 0.00003, lng: -46.63, time: t0.add(Duration(seconds: i)), accuracy: 5));
      }
      expect(tr.distanceM, closeTo(1334, 15));
      expect(tr.splits.length, 1);
      // Ponto com precisão ruim e salto impossível são descartados.
      expect(tr.add(Fix(lat: -23.53, lng: -46.63, time: t0.add(const Duration(seconds: 401)), accuracy: 80)), isFalse);
      expect(tr.add(Fix(lat: -23.50, lng: -46.63, time: t0.add(const Duration(seconds: 402)), accuracy: 5)), isFalse);
      expect(tr.avgPace(t0.add(const Duration(seconds: 400))), closeTo(300, 5));
    });

    test('pausa não conta tempo nem distância', () {
      final t0 = DateTime(2026, 11, 8, 7);
      final tr = RunTracker()..start(t0);
      tr.add(Fix(lat: 0, lng: 0, time: t0));
      tr.add(Fix(lat: 0.0001, lng: 0, time: t0.add(const Duration(seconds: 5))));
      tr.pause(t0.add(const Duration(seconds: 10)));
      expect(tr.add(Fix(lat: 0.01, lng: 0, time: t0.add(const Duration(seconds: 20)))), isFalse);
      tr.resume(t0.add(const Duration(seconds: 70)));
      expect(tr.elapsed(t0.add(const Duration(seconds: 80))), const Duration(seconds: 20));
      // Primeiro ponto após a pausa não liga com o anterior.
      tr.add(Fix(lat: 0.0005, lng: 0, time: t0.add(const Duration(seconds: 75))));
      expect(tr.distanceM, closeTo(11.1, 0.5));
    });
  });

  group('estatísticas', () {
    test('agrupa km por semana e calcula recordes', () {
      final today = DateTime(2026, 11, 8, 10); // domingo
      final ws = [
        run(DateTime(2026, 11, 7, 7), 10, const Duration(minutes: 58)),
        run(DateTime(2026, 11, 3, 7), 5, const Duration(minutes: 27)),
        run(DateTime(2026, 10, 30, 7), 6, const Duration(minutes: 36)),
        run(DateTime(2026, 10, 29, 18), 3, const Duration(minutes: 30), kind: WorkoutKind.caminhada),
      ];
      final st = Stats(ws, now: today);
      final weeks = st.weeks(3);
      expect(weeks.last.km, 15);
      expect(weeks[1].km, 6);
      final rec = st.records();
      expect(rec.best5k, const Duration(minutes: 27));
      expect(rec.best10k, const Duration(minutes: 58));
      expect(rec.longestKm, 10);
      expect(st.byKind(DateTime(2026, 10, 1), today).keys.first, WorkoutKind.corrida);
    });
  });
}
