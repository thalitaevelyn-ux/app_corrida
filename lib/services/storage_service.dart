import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/goal.dart';
import '../models/plan.dart';
import '../models/workout.dart';

/// Persistência local simples (SharedPreferences + JSON).
class StorageService {
  static const _kGoal = 'goal';
  static const _kPlan = 'plan';
  static const _kRecordings = 'recordings';
  static const _kLastAdjustWeek = 'lastAdjustWeek';
  static const _kFeeling = 'feeling';

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  Future<Goal?> loadGoal() async {
    final s = (await _p).getString(_kGoal);
    return s == null ? null : Goal.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  Future<void> saveGoal(Goal g) async => (await _p).setString(_kGoal, jsonEncode(g.toJson()));

  Future<TrainingPlan?> loadPlan() async {
    final s = (await _p).getString(_kPlan);
    if (s == null) return null;
    try {
      return TrainingPlan.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null; // formato antigo/corrompido: gera de novo
    }
  }

  Future<void> savePlan(TrainingPlan p) async => (await _p).setString(_kPlan, jsonEncode(p.toJson()));

  Future<int> lastAdjustedWeek() async => (await _p).getInt(_kLastAdjustWeek) ?? 0;
  Future<void> setLastAdjustedWeek(int w) async => (await _p).setInt(_kLastAdjustWeek, w);

  /// Sensação informada pelo usuário na semana atual ("cansado", "normal", "otimo").
  Future<String?> feeling() async => (await _p).getString(_kFeeling);
  Future<void> setFeeling(String? f) async {
    final p = await _p;
    f == null ? await p.remove(_kFeeling) : await p.setString(_kFeeling, f);
  }

  /// Dados extras das corridas gravadas pelo app (parciais e rota), indexados
  /// pelo horário de início; o Health Connect não guarda parciais.
  Future<Map<int, RecordingExtras>> loadRecordings() async {
    final s = (await _p).getString(_kRecordings);
    if (s == null) return {};
    final m = jsonDecode(s) as Map<String, dynamic>;
    return m.map((k, v) => MapEntry(int.parse(k), RecordingExtras.fromJson(v as Map<String, dynamic>)));
  }

  Future<void> saveRecording(DateTime start, RecordingExtras extras) async {
    final all = await loadRecordings();
    all[start.millisecondsSinceEpoch] = extras;
    // Mantém só as 200 mais recentes.
    final keys = all.keys.toList()..sort();
    while (keys.length > 200) {
      all.remove(keys.removeAt(0));
    }
    await (await _p).setString(_kRecordings, jsonEncode(all.map((k, v) => MapEntry('$k', v.toJson()))));
  }

  Future<void> clearAll() async => (await _p).clear();
}

class RecordingExtras {
  const RecordingExtras({required this.splits, required this.route});
  final List<Split> splits;
  final List<RoutePoint> route;

  Map<String, dynamic> toJson() => {
        'splits': splits.map((s) => s.toJson()).toList(),
        'route': route.map((r) => r.toJson()).toList(),
      };

  factory RecordingExtras.fromJson(Map<String, dynamic> j) => RecordingExtras(
        splits: (j['splits'] as List).map((e) => Split.fromJson(e as Map<String, dynamic>)).toList(),
        route: (j['route'] as List).map((e) => RoutePoint.fromJson(e as List)).toList(),
      );
}
