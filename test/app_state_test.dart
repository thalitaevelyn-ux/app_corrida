import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_corrida/models/goal.dart';
import 'package:app_corrida/models/plan.dart';
import 'package:app_corrida/models/workout.dart';
import 'package:app_corrida/services/cloud_repo.dart';
import 'package:app_corrida/services/health_service.dart';
import 'package:app_corrida/services/imported_store.dart';
import 'package:app_corrida/services/importers.dart';
import 'package:app_corrida/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'importers_test.dart' show gpx;

class FakeHealth extends HealthService {
  FakeHealth(this.items);
  List<Workout> items;
  int writes = 0;

  @override
  Future<HealthAvailability> availability() async => HealthAvailability.available;
  @override
  Future<bool> hasPermissions() async => true;
  @override
  Future<List<Workout>> readWorkouts({required DateTime from, required DateTime to}) async => List.of(items);
  @override
  Future<List<HrSample>> readHeartRate(DateTime from, DateTime to) async => [];
  @override
  Future<String?> writeRun({
    required DateTime start,
    required DateTime end,
    required double distanceM,
    int? kcal,
    required String title,
    List<WorkoutRouteLocation> route = const [],
    WorkoutKind kind = WorkoutKind.corrida,
    RecordingMethod recordingMethod = RecordingMethod.active,
  }) async {
    writes++;
    items = [...items, Workout(id: 'hc-$writes', kind: kind, title: title, start: start, end: end, source: 'Fast run', distanceM: distanceM)];
    return 'hc-$writes';
  }
}

class FakeCloud implements CloudRepo {
  FakeCloud([this.snap]);
  CloudSnapshot? snap;
  final upserts = <String>[];
  final profile = <String, Object?>{};
  Goal? savedGoal;
  TrainingPlan? savedPlan;

  @override
  Future<CloudSnapshot?> load() async => snap ?? const CloudSnapshot();
  @override
  Future<void> touchProfile(Map<String, Object?> fields) async => profile.addAll(fields);
  @override
  Future<void> saveGoal(Goal goal) async => savedGoal = goal;
  @override
  Future<void> savePlan(TrainingPlan plan) async => savedPlan = plan;
  @override
  Future<void> upsertWorkout(Workout w) async => upserts.add(w.id);
  @override
  Future<void> deleteWorkout(String id) async {}
}

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final now = DateTime(2026, 11, 8, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('fastrun');
  });
  tearDown(() => dir.delete(recursive: true));

  AppState make({required FakeHealth health, CloudRepo? cloud}) => AppState(
        health: health,
        cloud: cloud,
        importedStore: ImportedStore(dir: () async => dir),
        clock: () => now,
      );

  test('importa GPX e mostra na lista', () async {
    final s = make(health: FakeHealth([]));
    await s.init();
    final r = await s.importFile(bytesOf(gpx()), fileName: 'a.gpx');
    expect(r.mergedWithHealth, isFalse);
    expect(s.workouts.single.source, 'Zepp (GPX)');
    expect(s.workouts.single.imported, isTrue);
  });

  test('mesmo treino já no Health Connect não duplica e ganha rota/FC do arquivo', () async {
    final hc = Workout(
      id: 'hc-zepp',
      kind: WorkoutKind.corrida,
      title: 'Corrida',
      start: DateTime.utc(2026, 11, 7, 10, 0, 40).toLocal(), // 40 s de diferença
      end: DateTime.utc(2026, 11, 7, 10, 10).toLocal(),
      source: 'Zepp',
      distanceM: 2000,
    );
    final s = make(health: FakeHealth([hc]));
    await s.init();
    final r = await s.importFile(bytesOf(gpx()));
    expect(r.mergedWithHealth, isTrue);
    expect(s.workouts.length, 1);
    expect(s.workouts.single.id, 'hc-zepp');
    expect(s.workouts.single.route, isNotEmpty);
    expect(s.workouts.single.hr, isNotEmpty);
  });

  test('importar o mesmo arquivo duas vezes dá erro amigável', () async {
    final s = make(health: FakeHealth([]));
    await s.init();
    await s.importFile(bytesOf(gpx()));
    expect(() => s.importFile(bytesOf(gpx())), throwsA(isA<ImportException>()));
  });

  test('pode gravar o importado no Health Connect', () async {
    final h = FakeHealth([]);
    final s = make(health: h);
    await s.init();
    final r = await s.importFile(bytesOf(gpx()), saveToHealth: true);
    expect(r.savedToHealth, isTrue);
    expect(h.writes, 1);
    // Depois de gravar, o HC devolve o treino; a lista continua com 1 item.
    expect(s.workouts.length, 1);
  });

  test('importados persistem no aparelho e sobem para a nuvem', () async {
    final cloud = FakeCloud();
    final s = make(health: FakeHealth([]), cloud: cloud);
    await s.init();
    final r = await s.importFile(bytesOf(gpx()));
    await Future<void>.delayed(Duration.zero);
    expect(cloud.upserts, contains(r.workout.id));
    expect(cloud.profile['importedCount'], 1);
    final again = make(health: FakeHealth([]));
    await again.init();
    expect(again.importedWorkouts.single.id, r.workout.id);
  });

  test('celular novo: restaura objetivo, plano e importados da nuvem', () async {
    final w = importActivity(bytesOf(gpx()));
    const goal = Goal(type: GoalType.distancia, distanceKm: 10, daysPerWeek: 3);
    final plan = TrainingPlan(
      startDate: DateTime(2026, 11, 2),
      summary: 'Plano da nuvem',
      estimatedLevel: 'Iniciante',
      paces: const Paces(easy: '7:00 /km', threshold: '6:00 /km', interval: '5:30 /km', long: '7:10 /km'),
      weeks: const [PlanWeek(number: 1, focus: 'Base', totalKm: 10, sessions: [])],
      source: 'ia',
      updatedAt: DateTime(2026, 11, 2),
    );
    final s = make(health: FakeHealth([]), cloud: FakeCloud(CloudSnapshot(goal: goal, plan: plan, imported: [w])));
    await s.init();
    expect(s.goal?.distanceKm, 10);
    expect(s.plan?.summary, 'Plano da nuvem');
    expect(s.workouts.single.id, w.id);
  });

  test('primeiro login: envia para a nuvem o que já existia no aparelho', () async {
    final local = make(health: FakeHealth([]));
    await local.init();
    await local.setGoal(const Goal(type: GoalType.base, distanceKm: 20, daysPerWeek: 3));
    final cloud = FakeCloud();
    final logged = make(health: FakeHealth([]), cloud: cloud);
    await logged.init();
    expect(cloud.savedGoal?.type, GoalType.base);
    expect(cloud.savedPlan, isNotNull);
  });
}
