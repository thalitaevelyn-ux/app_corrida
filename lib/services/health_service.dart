import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../models/workout.dart';

enum HealthAvailability { available, needsInstallOrUpdate, unavailable }

/// Acesso ao Health Connect: permissões, leitura de treinos e FC, escrita de
/// corridas gravadas pelo app.
class HealthService {
  HealthService({Health? health}) : _health = health ?? Health();
  final Health _health;
  bool _configured = false;

  static const _readTypes = [HealthDataType.WORKOUT, HealthDataType.HEART_RATE];
  static const _writeTypes = [HealthDataType.WORKOUT, HealthDataType.WORKOUT_ROUTE];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<HealthAvailability> availability() async {
    await _ensureConfigured();
    final s = await _health.getHealthConnectSdkStatus();
    switch (s) {
      case HealthConnectSdkStatus.sdkAvailable:
        return HealthAvailability.available;
      case HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired:
        return HealthAvailability.needsInstallOrUpdate;
      default:
        return HealthAvailability.unavailable;
    }
  }

  /// Abre a Play Store no Health Connect (Android 9–13).
  Future<void> installHealthConnect() => _health.installHealthConnect();

  Future<bool> hasPermissions() async {
    await _ensureConfigured();
    final types = [..._readTypes, ..._writeTypes];
    final perms = [
      for (final t in types) _writeTypes.contains(t) ? HealthDataAccess.READ_WRITE : HealthDataAccess.READ,
    ];
    return await _health.hasPermissions(types, permissions: perms) ?? false;
  }

  /// Pede leitura de treinos/FC, escrita de treinos/rotas e acesso ao histórico.
  Future<bool> requestPermissions() async {
    await _ensureConfigured();
    final types = [HealthDataType.WORKOUT, HealthDataType.HEART_RATE, HealthDataType.WORKOUT_ROUTE];
    final perms = [HealthDataAccess.READ_WRITE, HealthDataAccess.READ, HealthDataAccess.READ_WRITE];
    final ok = await _health.requestAuthorization(types, permissions: perms);
    if (ok && !await _health.isHealthDataHistoryAuthorized()) {
      // Sem isso o Health Connect só entrega 30 dias anteriores à permissão.
      await _health.requestHealthDataHistoryAuthorization();
    }
    return ok;
  }

  Future<List<Workout>> readWorkouts({required DateTime from, required DateTime to}) async {
    await _ensureConfigured();
    final points = await _health.getHealthDataFromTypes(types: const [HealthDataType.WORKOUT], startTime: from, endTime: to);
    final list = <Workout>[];
    for (final p in _health.removeDuplicates(points)) {
      final v = p.value;
      if (v is! WorkoutHealthValue) continue;
      final kind = kindFromActivity(v.workoutActivityType);
      list.add(Workout(
        id: p.uuid,
        kind: kind,
        title: titleFor(kind, v.workoutActivityType),
        start: p.dateFrom,
        end: p.dateTo,
        source: _sourceLabel(p.sourceName, p.sourceId),
        distanceM: (v.totalDistance ?? p.workoutSummary?.totalDistance)?.toDouble(),
        kcal: v.totalEnergyBurned ?? p.workoutSummary?.totalEnergyBurned.toInt(),
        steps: v.totalSteps,
      ));
    }
    list.sort((a, b) => b.start.compareTo(a.start));
    return list;
  }

  Future<List<HrSample>> readHeartRate(DateTime from, DateTime to) async {
    await _ensureConfigured();
    final points = await _health.getHealthDataFromTypes(types: const [HealthDataType.HEART_RATE], startTime: from, endTime: to);
    return [
      for (final p in points)
        if (p.value is NumericHealthValue) HrSample(p.dateFrom, (p.value as NumericHealthValue).numericValue.toDouble()),
    ]..sort((a, b) => a.time.compareTo(b.time));
  }

  /// Grava uma corrida do app no Health Connect, com rota quando houver.
  /// Retorna o id do treino criado.
  Future<String?> writeRun({
    required DateTime start,
    required DateTime end,
    required double distanceM,
    int? kcal,
    required String title,
    List<WorkoutRouteLocation> route = const [],
  }) async {
    await _ensureConfigured();
    String? builder;
    if (route.length >= 2) {
      try {
        builder = await _health.startWorkoutRoute();
        await _health.insertWorkoutRouteData(builderId: builder, locations: route);
      } catch (e) {
        debugPrint('Rota não gravada: $e');
        builder = null;
      }
    }
    final id = await _health.writeWorkoutDataUUID(
      activityType: HealthWorkoutActivityType.RUNNING,
      start: start,
      end: end,
      totalDistance: distanceM.round(),
      totalEnergyBurned: kcal,
      title: title,
      recordingMethod: RecordingMethod.active,
    );
    if (builder != null) {
      try {
        if (id != null && id != 'null') {
          await _health.finishWorkoutRoute(builderId: builder, workoutUuid: id);
        } else {
          await _health.discardWorkoutRoute(builder);
        }
      } catch (e) {
        debugPrint('Falha ao finalizar rota: $e');
      }
    }
    return id == 'null' ? null : id;
  }

  static WorkoutKind kindFromActivity(HealthWorkoutActivityType t) {
    final n = t.name;
    if (n.startsWith('RUNNING')) return WorkoutKind.corrida;
    if (n.startsWith('WALKING') || n == 'HIKING') return WorkoutKind.caminhada;
    if (n.startsWith('BIKING') || n.contains('CYCLING')) return WorkoutKind.bike;
    const gym = {
      'STRENGTH_TRAINING',
      'WEIGHTLIFTING',
      'TRADITIONAL_STRENGTH_TRAINING',
      'FUNCTIONAL_STRENGTH_TRAINING',
      'HIGH_INTENSITY_INTERVAL_TRAINING',
      'CALISTHENICS',
      'PILATES',
      'YOGA',
      'CROSS_TRAINING',
      'CORE_TRAINING',
      'ELLIPTICAL',
      'STAIR_CLIMBING_MACHINE',
    };
    if (gym.contains(n)) return WorkoutKind.academia;
    return WorkoutKind.outro;
  }

  static String titleFor(WorkoutKind k, HealthWorkoutActivityType t) {
    switch (t.name) {
      case 'RUNNING_TREADMILL':
        return 'Corrida na esteira';
      case 'WALKING_TREADMILL':
        return 'Caminhada na esteira';
      case 'BIKING_STATIONARY':
        return 'Bike ergométrica';
      case 'HIKING':
        return 'Trilha';
      case 'YOGA':
        return 'Yoga';
      case 'PILATES':
        return 'Pilates';
      case 'HIGH_INTENSITY_INTERVAL_TRAINING':
        return 'HIIT';
      case 'SWIMMING':
      case 'SWIMMING_POOL':
      case 'SWIMMING_OPEN_WATER':
        return 'Natação';
    }
    switch (k) {
      case WorkoutKind.corrida:
        return 'Corrida';
      case WorkoutKind.caminhada:
        return 'Caminhada';
      case WorkoutKind.bike:
        return 'Pedal';
      case WorkoutKind.academia:
        return 'Fortalecimento';
      case WorkoutKind.outro:
        return 'Treino';
    }
  }

  static String _sourceLabel(String name, String id) {
    const known = {
      'com.sec.android.app.shealth': 'Samsung Health',
      'com.google.android.apps.fitness': 'Google Fit',
      'com.strava': 'Strava',
      'com.garmin.android.apps.connectmobile': 'Garmin Connect',
      'com.xiaomi.wearable': 'Mi Fitness',
      'com.huawei.health': 'Huawei Health',
      'com.fitbit.FitbitMobile': 'Fitbit',
      'com.exemplo.app_corrida': 'App Corrida',
    };
    return known[id] ?? known[name] ?? (name.isNotEmpty ? name : 'Health Connect');
  }
}
