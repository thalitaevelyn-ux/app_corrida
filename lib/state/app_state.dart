import 'package:flutter/foundation.dart';

import '../models/goal.dart';
import '../models/plan.dart';
import '../models/workout.dart';
import '../services/fitness.dart';
import '../services/health_service.dart';
import '../services/local_planner.dart';
import '../services/plan_api.dart';
import '../services/plan_progress.dart';
import '../services/storage_service.dart';

enum HealthState { unknown, unavailable, needsInstall, needsPermission, ready }

class AppState extends ChangeNotifier {
  AppState({HealthService? health, StorageService? storage, PlanApi? api, DateTime Function()? clock})
      : _health = health ?? HealthService(),
        _storage = storage ?? StorageService(),
        _api = api ?? PlanApi(),
        _clock = clock ?? DateTime.now;

  final HealthService _health;
  final StorageService _storage;
  final PlanApi _api;
  final DateTime Function() _clock;

  bool loading = true;
  bool syncing = false;
  bool generating = false;
  String? message;

  HealthState healthState = HealthState.unknown;
  Goal? goal;
  TrainingPlan? plan;
  List<Workout> workouts = [];
  String? feeling;
  Map<int, RecordingExtras> _extras = {};

  DateTime get now => _clock();
  FitnessProfile get fitness => estimateFitness(workouts, now: now);
  PlanProgress? get progress => plan == null ? null : PlanProgress(plan!, workouts);
  HealthService get health => _health;

  Future<void> init() async {
    goal = await _storage.loadGoal();
    plan = await _storage.loadPlan();
    feeling = await _storage.feeling();
    _extras = await _storage.loadRecordings();
    loading = false;
    notifyListeners();
    await _checkHealth();
    if (healthState == HealthState.ready) {
      await sync();
      await maybeWeeklyAdjust();
    }
  }

  Future<void> _checkHealth() async {
    try {
      switch (await _health.availability()) {
        case HealthAvailability.unavailable:
          healthState = HealthState.unavailable;
        case HealthAvailability.needsInstallOrUpdate:
          healthState = HealthState.needsInstall;
        case HealthAvailability.available:
          healthState = await _health.hasPermissions() ? HealthState.ready : HealthState.needsPermission;
      }
    } catch (e) {
      debugPrint('Health Connect: $e');
      healthState = HealthState.unavailable;
    }
    notifyListeners();
  }

  Future<void> connectHealth() async {
    if (healthState == HealthState.needsInstall) {
      await _health.installHealthConnect();
      return;
    }
    try {
      await _health.requestPermissions();
    } catch (e) {
      message = 'Não foi possível pedir as permissões: $e';
    }
    await _checkHealth();
    if (healthState == HealthState.ready) await sync();
  }

  /// Lê os últimos 180 dias de treinos do Health Connect.
  Future<void> sync() async {
    if (syncing) return;
    syncing = true;
    notifyListeners();
    try {
      final t = now;
      final list = await _health.readWorkouts(from: t.subtract(const Duration(days: 180)), to: t);
      for (final w in list) {
        final x = _extras[w.start.millisecondsSinceEpoch];
        if (x != null) {
          w.splits = x.splits;
          w.route = x.route;
        }
      }
      workouts = list;
    } catch (e) {
      message = 'Erro ao ler o Health Connect: $e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Carrega a FC do treino (sob demanda, para a tela de detalhe).
  Future<void> loadDetail(Workout w) async {
    if (w.hr.isNotEmpty) return;
    try {
      w.hr = await _health.readHeartRate(w.start, w.end);
      notifyListeners();
    } catch (e) {
      debugPrint('FC indisponível: $e');
    }
  }

  List<Workout> filtered(WorkoutKind? kind) => kind == null ? workouts : workouts.where((w) => w.kind == kind).toList();

  // ---------------------------------------------------------------- plano

  /// Salva o objetivo e gera o plano: IA quando configurada, regras como reserva.
  Future<void> setGoal(Goal g) async {
    goal = g;
    await _storage.saveGoal(g);
    await _storage.setLastAdjustedWeek(0);
    await generatePlan();
  }

  Future<void> generatePlan() async {
    final g = goal;
    if (g == null) return;
    generating = true;
    message = null;
    notifyListeners();
    final fit = fitness;
    final local = const LocalPlanner().generate(g, fit, now: now);
    TrainingPlan result = local;
    if (PlanApiConfig.enabled) {
      try {
        final r = await _api.generate(
          goal: g.toApiJson(),
          fitness: fit.toApiJson(),
          recentWorkouts: workouts.take(40).map((w) => w.toSummaryJson()).toList(),
          startDate: local.startDate,
        );
        result = TrainingPlan(
          startDate: local.startDate,
          summary: r.summary,
          estimatedLevel: r.level.isEmpty ? fit.levelLabel : r.level,
          paces: r.paces,
          weeks: r.weeks,
          source: 'ia',
          updatedAt: now,
        );
      } catch (e) {
        message = 'IA indisponível, usamos o plano por regras. ($e)';
      }
    }
    plan = result;
    await _storage.savePlan(result);
    generating = false;
    notifyListeners();
  }

  Future<void> setFeeling(String f) async {
    feeling = f;
    await _storage.setFeeling(f);
    notifyListeners();
  }

  /// Uma vez por semana, ao começar uma semana nova, ajusta o restante do plano
  /// com base no que foi feito na semana anterior.
  Future<void> maybeWeeklyAdjust({bool force = false}) async {
    final p = plan, g = goal;
    if (p == null || g == null) return;
    final current = p.currentWeek(now);
    final finished = current - 1;
    if (finished < 1) return;
    if (!force && await _storage.lastAdjustedWeek() >= finished) return;

    generating = true;
    notifyListeners();
    TrainingPlan updated = const LocalAdjuster().adjust(p, workouts, finished, feeling: feeling, now: now);
    if (PlanApiConfig.enabled) {
      try {
        final r = await _api.adjust(
          goal: g.toApiJson(),
          plan: p,
          nextWeek: current,
          lastWeekReport: PlanProgress(p, workouts).weekReport(finished, now: now),
          feeling: feeling,
        );
        final byNumber = {for (final w in r.weeks) w.number: w};
        updated = p.copyWith(
          weeks: [for (final w in p.weeks) w.number >= current ? (byNumber[w.number] ?? w) : w],
          paces: r.paces,
          adjustmentNote: r.adjustmentNote ?? 'Plano ajustado pela IA.',
          source: 'ia',
          updatedAt: now,
        );
      } catch (e) {
        debugPrint('Ajuste por IA falhou, usando regras: $e');
      }
    }
    plan = updated;
    await _storage.savePlan(updated);
    await _storage.setLastAdjustedWeek(finished);
    await _storage.setFeeling(null);
    feeling = null;
    generating = false;
    notifyListeners();
  }

  // -------------------------------------------------------------- gravação

  Future<bool> saveRecordedRun({
    required DateTime start,
    required DateTime end,
    required double distanceM,
    required int kcal,
    required List<Split> splits,
    required List<RoutePoint> route,
    required Future<String?> Function() writeToHealth,
  }) async {
    await _storage.saveRecording(start, RecordingExtras(splits: splits, route: route));
    _extras = await _storage.loadRecordings();
    String? id;
    try {
      id = await writeToHealth();
    } catch (e) {
      message = 'Corrida salva no app, mas não no Health Connect: $e';
    }
    await sync();
    // Se a leitura ainda não trouxe a corrida (atraso do Health Connect),
    // mostramos a versão local para a tela inicial não ficar desatualizada.
    if (!workouts.any((w) => w.start.millisecondsSinceEpoch == start.millisecondsSinceEpoch)) {
      workouts = [
        Workout(
          id: id ?? 'local-${start.millisecondsSinceEpoch}',
          kind: WorkoutKind.corrida,
          title: 'Corrida',
          start: start,
          end: end,
          source: 'Fast run',
          distanceM: distanceM,
          kcal: kcal,
          splits: splits,
          route: route,
        ),
        ...workouts,
      ];
      notifyListeners();
    }
    return id != null;
  }

  void clearMessage() {
    message = null;
    notifyListeners();
  }

  Future<void> resetAll() async {
    await _storage.clearAll();
    goal = null;
    plan = null;
    feeling = null;
    notifyListeners();
  }
}
