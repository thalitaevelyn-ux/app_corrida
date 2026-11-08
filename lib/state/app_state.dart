import 'package:flutter/foundation.dart';
import 'package:health/health.dart' show RecordingMethod;

import '../models/goal.dart';
import '../models/plan.dart';
import '../models/workout.dart';
import '../services/cloud_repo.dart';
import '../services/fitness.dart';
import '../services/health_service.dart';
import '../services/imported_store.dart';
import '../services/importers.dart';
import '../services/local_planner.dart';
import '../services/plan_api.dart';
import '../services/plan_progress.dart';
import '../services/storage_service.dart';

enum HealthState { unknown, unavailable, needsInstall, needsPermission, ready }

/// Resultado de uma importação de arquivo, para a tela explicar o que houve.
class ImportResult {
  const ImportResult(this.workout, {this.mergedWithHealth = false, this.savedToHealth = false});
  final Workout workout;

  /// O treino já estava no Health Connect: só juntamos rota/FC/parciais.
  final bool mergedWithHealth;
  final bool savedToHealth;
}

class AppState extends ChangeNotifier {
  AppState({
    HealthService? health,
    StorageService? storage,
    PlanApi? api,
    ImportedStore? importedStore,
    CloudRepo? cloud,
    DateTime Function()? clock,
    this.appVersion = '',
  })  : _health = health ?? HealthService(),
        _storage = storage ?? StorageService(),
        _api = api ?? PlanApi(),
        _importedStore = importedStore ?? ImportedStore(),
        _cloud = cloud ?? const LocalOnlyRepo(),
        _clock = clock ?? DateTime.now;

  final HealthService _health;
  final StorageService _storage;
  final PlanApi _api;
  final ImportedStore _importedStore;
  final CloudRepo _cloud;
  final DateTime Function() _clock;
  final String appVersion;

  bool loading = true;
  bool syncing = false;
  bool generating = false;
  String? message;

  HealthState healthState = HealthState.unknown;
  Goal? goal;
  TrainingPlan? plan;
  String? feeling;
  Map<int, RecordingExtras> _extras = {};

  /// Treinos lidos do Health Connect e importados de arquivo.
  List<Workout> _healthWorkouts = [];
  List<Workout> _imported = [];

  /// Lista unificada (mais recentes primeiro), sem duplicar o mesmo treino.
  List<Workout> workouts = [];
  List<Workout> get importedWorkouts => List.unmodifiable(_imported);

  DateTime get now => _clock();
  FitnessProfile get fitness => estimateFitness(workouts, now: now);
  PlanProgress? get progress => plan == null ? null : PlanProgress(plan!, workouts);
  HealthService get health => _health;

  Future<void> init() async {
    goal = await _storage.loadGoal();
    plan = await _storage.loadPlan();
    feeling = await _storage.feeling();
    _extras = await _storage.loadRecordings();
    _imported = await _importedStore.load();
    _merge();
    loading = false;
    notifyListeners();
    await _syncCloud();
    await _checkHealth();
    if (healthState == HealthState.ready) await sync();
    await maybeWeeklyAdjust();
  }

  /// Traz da nuvem o que faltar aqui (celular novo) e envia o que só existe aqui.
  Future<void> _syncCloud() async {
    try {
      final snap = await _cloud.load();
      if (snap != null) {
        var changed = false;
        if (goal == null && snap.goal != null) {
          goal = snap.goal;
          await _storage.saveGoal(goal!);
          changed = true;
        } else if (goal != null && snap.goal == null) {
          await _cloud.saveGoal(goal!);
        }
        final local = plan, remote = snap.plan;
        if (remote != null && (local == null || remote.updatedAt.isAfter(local.updatedAt))) {
          plan = remote;
          await _storage.savePlan(remote);
          changed = true;
        } else if (local != null && (remote == null || local.updatedAt.isAfter(remote.updatedAt))) {
          await _cloud.savePlan(local);
        }
        final localIds = {for (final w in _imported) w.id};
        final remoteIds = {for (final w in snap.imported) w.id};
        final missingHere = snap.imported.where((w) => !localIds.contains(w.id)).toList();
        if (missingHere.isNotEmpty) {
          _imported = [..._imported, ...missingHere];
          await _importedStore.save(_imported);
          changed = true;
        }
        for (final w in _imported.where((w) => !remoteIds.contains(w.id))) {
          await _cloud.upsertWorkout(w);
        }
        if (changed) {
          _merge();
          notifyListeners();
        }
      }
      await _cloud.touchProfile({
        'appVersion': appVersion,
        'goalType': goal?.type.name,
        'planSource': plan?.source,
        'importedCount': _imported.length,
      });
    } catch (e) {
      debugPrint('Sincronização com a nuvem falhou (segue offline): $e');
    }
  }

  void _merge() {
    final merged = <Workout>[..._healthWorkouts];
    for (final imp in _imported) {
      final i = merged.indexWhere((h) => !h.imported && h.sameSessionAs(imp));
      if (i < 0) {
        merged.add(imp);
        continue;
      }
      // Mesmo treino nas duas fontes: mantém o do Health Connect e completa
      // com os detalhes do arquivo (rota, FC, parciais).
      final h = merged[i];
      if (h.route.isEmpty) h.route = imp.route;
      if (h.splits.isEmpty) h.splits = imp.splits;
      if (h.hr.isEmpty) h.hr = imp.hr;
    }
    merged.sort((a, b) => b.start.compareTo(a.start));
    workouts = merged;
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
      _healthWorkouts = list;
      _merge();
    } catch (e) {
      message = 'Erro ao ler o Health Connect: $e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- importação

  /// Importa um arquivo GPX/TCX/FIT. Lança [ImportException] com mensagem amigável.
  Future<ImportResult> importFile(Uint8List bytes, {String fileName = '', bool saveToHealth = false}) async {
    final w = importActivity(bytes, fileName: fileName);
    if (_imported.any((x) => x.sameSessionAs(w))) {
      throw ImportException('Este treino já foi importado.');
    }
    final inHealth = _healthWorkouts.any((h) => h.sameSessionAs(w));
    var saved = false;
    if (saveToHealth && !inHealth && healthState == HealthState.ready) {
      try {
        final id = await _health.writeRun(
          start: w.start,
          end: w.end,
          distanceM: w.distanceM ?? 0,
          kcal: w.kcal,
          title: w.title,
          kind: w.kind,
          recordingMethod: RecordingMethod.unknown,
        );
        saved = id != null;
      } catch (e) {
        debugPrint('Não gravou no Health Connect: $e');
      }
    }
    _imported = [..._imported, w];
    await _importedStore.save(_imported);
    _merge();
    notifyListeners();
    _cloud.upsertWorkout(w).catchError((Object e) => debugPrint('Nuvem: $e'));
    _cloud.touchProfile({'importedCount': _imported.length, 'lastImportFormat': w.id.split('-')[1]}).catchError((_) {});
    if (saved) await sync();
    return ImportResult(w, mergedWithHealth: inHealth, savedToHealth: saved);
  }

  Future<void> deleteImported(String id) async {
    _imported = _imported.where((w) => w.id != id).toList();
    await _importedStore.save(_imported);
    _merge();
    notifyListeners();
    _cloud.deleteWorkout(id).catchError((Object e) => debugPrint('Nuvem: $e'));
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
    _cloud.saveGoal(g).catchError((Object e) => debugPrint('Nuvem: $e'));
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
    _cloud.savePlan(result).catchError((Object e) => debugPrint('Nuvem: $e'));
    _cloud.touchProfile({'goalType': g.type.name, 'planSource': result.source}).catchError((_) {});
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
    _cloud.savePlan(updated).catchError((Object e) => debugPrint('Nuvem: $e'));
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
      _healthWorkouts = [
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
        ..._healthWorkouts,
      ];
      _merge();
      notifyListeners();
    }
    return id != null;
  }

  void clearMessage() {
    message = null;
    notifyListeners();
  }

  /// Exclui a conta no servidor (dados na nuvem + login) e limpa o aparelho.
  /// Quem chama deve sair da conta em seguida (AuthService.signOut).
  Future<void> deleteAccount() async {
    await _api.deleteAccount();
    await resetAll();
  }

  /// Apaga os dados guardados neste aparelho (a conta e a nuvem são tratadas
  /// em AuthService.deleteAccount).
  Future<void> resetAll() async {
    await _storage.clearAll();
    await _importedStore.clear();
    goal = null;
    plan = null;
    feeling = null;
    _imported = [];
    _merge();
    notifyListeners();
  }
}
