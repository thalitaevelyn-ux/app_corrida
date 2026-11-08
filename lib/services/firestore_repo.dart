import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/goal.dart';
import '../models/plan.dart';
import '../models/workout.dart';
import 'cloud_repo.dart';

/// Dados do usuário no Firestore:
///   users/{uid}                 perfil, objetivo, plano (JSON) e dados de uso
///   users/{uid}/workouts/{id}   treinos importados de arquivo (JSON)
///
/// Plano e treinos vão como texto JSON: o Firestore não aceita listas dentro
/// de listas (a rota é uma lista de pares lat/lng) e assim o formato é o mesmo
/// do aparelho. As regras em firestore.rules só deixam cada usuário ler e
/// escrever os próprios documentos.
class FirestoreRepo implements CloudRepo {
  FirestoreRepo(this.uid, {FirebaseFirestore? db, this.email, this.name}) : _db = db ?? FirebaseFirestore.instance;
  final String uid;
  final String? email;
  final String? name;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _user => _db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get _workouts => _user.collection('workouts');

  @override
  Future<CloudSnapshot?> load() async {
    final doc = await _user.get();
    final d = doc.data();
    final ws = await _workouts.get();
    return CloudSnapshot(
      goal: d?['goal'] is String ? Goal.fromJson(jsonDecode(d!['goal'] as String) as Map<String, dynamic>) : null,
      plan: d?['plan'] is String ? _plan(d!['plan'] as String) : null,
      imported: [
        for (final w in ws.docs)
          if (w.data()['data'] is String) Workout.fromJson(jsonDecode(w.data()['data'] as String) as Map<String, dynamic>),
      ],
    );
  }

  TrainingPlan? _plan(String s) {
    try {
      return TrainingPlan.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> touchProfile(Map<String, Object?> fields) => _user.set({
        ...fields,
        'email': ?email,
        'name': ?name,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// Chamado uma vez, no cadastro: registra criação e aceite da política.
  Future<void> createProfile({required bool acceptedTerms}) => _user.set({
        'email': ?email,
        'name': ?name,
        'createdAt': FieldValue.serverTimestamp(),
        if (acceptedTerms) 'termsAcceptedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<bool> hasAcceptedTerms() async => (await _user.get()).data()?['termsAcceptedAt'] != null;

  @override
  Future<void> saveGoal(Goal goal) => _user.set({'goal': jsonEncode(goal.toJson())}, SetOptions(merge: true));

  @override
  Future<void> savePlan(TrainingPlan plan) => _user.set({
        'plan': jsonEncode(plan.toJson()),
        'planSource': plan.source,
        'planUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Future<void> upsertWorkout(Workout w) => _workouts.doc(w.id).set({
        'data': jsonEncode(w.toJson()),
        'kind': w.kind.name,
        'source': w.source,
        'start': Timestamp.fromDate(w.start),
        'importedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteWorkout(String id) => _workouts.doc(id).delete();
}
