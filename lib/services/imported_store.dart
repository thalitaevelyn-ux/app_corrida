import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/workout.dart';

/// Treinos importados de arquivo, guardados num JSON no armazenamento do app.
/// (O Health Connect não guarda treinos de terceiros por nós, e a rota + FC
/// de um treino podem ter dezenas de KB.)
class ImportedStore {
  ImportedStore({Future<Directory> Function()? dir}) : _dir = dir ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _dir;

  Future<File> get _file async => File('${(await _dir()).path}/imported_workouts.json');

  Future<List<Workout>> load() async {
    try {
      final f = await _file;
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return [for (final e in list) Workout.fromJson(Map<String, dynamic>.from(e as Map))];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Workout> all) async {
    final f = await _file;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final w in all) w.toJson()]));
    await tmp.rename(f.path); // troca atômica: não corrompe se o app fechar no meio
  }

  Future<void> clear() async {
    final f = await _file;
    if (await f.exists()) await f.delete();
  }
}
