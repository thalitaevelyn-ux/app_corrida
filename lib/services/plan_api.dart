import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/plan.dart';

/// Configuração do backend de IA (config/app.json):
///   PLAN_API_URL   endereço do servidor
///   PLAN_API_TOKEN só para o modo sem login (sem Firebase); com login, o app
///                  envia o token do usuário do Firebase.
class PlanApiConfig {
  static const url = String.fromEnvironment('PLAN_API_URL');
  static const token = String.fromEnvironment('PLAN_API_TOKEN');
  static bool get enabled => url.isNotEmpty;
}

class PlanApiException implements Exception {
  PlanApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Resposta do backend: plano (semanas, paces, resumo) e, no ajuste, a nota.
class PlanApiResult {
  PlanApiResult({
    required this.summary,
    required this.level,
    required this.paces,
    required this.weeks,
    this.adjustmentNote,
  });
  final String summary;
  final String level;
  final Paces paces;
  final List<PlanWeek> weeks;
  final String? adjustmentNote;
}

class PlanApi {
  PlanApi({http.Client? client, this.idToken}) : _client = client ?? http.Client();
  final http.Client _client;

  /// Token do usuário logado (Firebase). Sem ele, usa PLAN_API_TOKEN.
  final Future<String?> Function()? idToken;

  /// Exclui a conta e todos os dados do usuário no servidor (exigência da Play Store).
  Future<void> deleteAccount() async {
    await _send('DELETE', '/v1/conta', null);
  }

  Future<PlanApiResult> generate({
    required Map<String, dynamic> goal,
    required Map<String, dynamic> fitness,
    required List<Map<String, dynamic>> recentWorkouts,
    required DateTime startDate,
  }) async {
    final body = await _post('/v1/plano/gerar', {
      'objetivo': goal,
      'perfil': fitness,
      'treinosRecentes': recentWorkouts,
      'inicio': startDate.toIso8601String().substring(0, 10),
    });
    return _parse(body);
  }

  Future<PlanApiResult> adjust({
    required Map<String, dynamic> goal,
    required TrainingPlan plan,
    required int nextWeek,
    required Map<String, dynamic> lastWeekReport,
    String? feeling,
  }) async {
    final body = await _post('/v1/plano/ajustar', {
      'objetivo': goal,
      'paces': plan.paces.toJson(),
      'semanaAtual': nextWeek,
      'semanasRestantes': plan.weeks.where((w) => w.number >= nextWeek).map((w) => w.toJson()).toList(),
      'relatorioSemanaAnterior': lastWeekReport,
      'sensacao': ?feeling,
    });
    return _parse(body);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> payload) => _send('POST', path, payload);

  Future<Map<String, dynamic>> _send(String method, String path, Map<String, dynamic>? payload) async {
    final user = await idToken?.call();
    final bearer = (user != null && user.isNotEmpty) ? user : PlanApiConfig.token;
    final http.Response res;
    try {
      final req = http.Request(method, Uri.parse('${PlanApiConfig.url}$path'))
        ..headers.addAll({
          'content-type': 'application/json',
          if (bearer.isNotEmpty) 'authorization': 'Bearer $bearer',
        });
      if (payload != null) req.body = jsonEncode(payload);
      // A IA pode levar alguns minutos num plano longo (e o servidor gratuito acorda devagar).
      res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(minutes: 4)));
    } catch (e) {
      throw PlanApiException('Sem conexão com o servidor do plano ($e).');
    }
    if (res.statusCode != 200) {
      String msg = 'Servidor respondeu ${res.statusCode}.';
      try {
        msg = (jsonDecode(res.body) as Map)['erro'] as String? ?? msg;
      } catch (_) {}
      throw PlanApiException(msg);
    }
    if (res.bodyBytes.isEmpty) return const {};
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  PlanApiResult _parse(Map<String, dynamic> j) => PlanApiResult(
        summary: j['resumo'] as String,
        level: (j['nivelEstimado'] as String?) ?? '',
        paces: Paces.fromJson(j['paces'] as Map<String, dynamic>),
        weeks: (j['semanas'] as List).map((e) => PlanWeek.fromJson(e as Map<String, dynamic>)).toList(),
        adjustmentNote: j['explicacaoAjuste'] as String?,
      );
}
