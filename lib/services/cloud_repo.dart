import '../models/goal.dart';
import '../models/plan.dart';
import '../models/workout.dart';

/// O que fica salvo na nuvem para o usuário (para trocar de celular sem perder).
class CloudSnapshot {
  const CloudSnapshot({this.goal, this.plan, this.imported = const []});
  final Goal? goal;
  final TrainingPlan? plan;
  final List<Workout> imported;
}

/// Armazenamento por usuário. A implementação real é Firestore
/// (lib/services/firestore_repo.dart); [LocalOnlyRepo] não sincroniza nada.
abstract class CloudRepo {
  Future<CloudSnapshot?> load();

  /// Atualiza dados de uso do perfil (último acesso, versão, origem do plano...).
  Future<void> touchProfile(Map<String, Object?> fields);
  Future<void> saveGoal(Goal goal);
  Future<void> savePlan(TrainingPlan plan);
  Future<void> upsertWorkout(Workout w);
  Future<void> deleteWorkout(String id);
}

class LocalOnlyRepo implements CloudRepo {
  const LocalOnlyRepo();
  @override
  Future<CloudSnapshot?> load() async => null;
  @override
  Future<void> touchProfile(Map<String, Object?> fields) async {}
  @override
  Future<void> saveGoal(Goal goal) async {}
  @override
  Future<void> savePlan(TrainingPlan plan) async {}
  @override
  Future<void> upsertWorkout(Workout w) async {}
  @override
  Future<void> deleteWorkout(String id) async {}
}
