import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/workout.dart';
import '../services/importers.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import 'record_screen.dart';
import 'workout_detail_screen.dart';

/// Menu do botão "Adicionar treino".
Future<void> showAddWorkoutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('Importar arquivo'),
          subtitle: const Text('GPX, TCX ou FIT exportado do Zepp, Garmin, Strava, Coros...'),
          onTap: () {
            Navigator.pop(ctx);
            pickAndImport(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.watch),
          title: const Text('Conectar relógio ou app'),
          subtitle: const Text('Sincronizar automático pelo Health Connect'),
          onTap: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectGuideScreen()));
          },
        ),
        ListTile(
          leading: const Icon(Icons.gps_fixed),
          title: const Text('Gravar com o GPS do celular'),
          subtitle: const Text('Para quando você corre com o celular'),
          onTap: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const RecordScreen()));
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

Future<void> pickAndImport(BuildContext context) async {
  final List<PlatformFile> files;
  try {
    // FileType.any: o Android não conhece os tipos MIME de GPX/TCX/FIT, então
    // filtrar por extensão esconderia os arquivos em alguns aparelhos.
    files = await FilePicker.pickFiles(dialogTitle: 'Escolha o arquivo do treino');
  } catch (e) {
    if (context.mounted) _snack(context, 'Não foi possível abrir os arquivos: $e');
    return;
  }
  if (files.isEmpty || !context.mounted) return;
  final f = files.first;
  final bytes = await f.xFile.readAsBytes();
  if (context.mounted) await previewAndImport(context, bytes, f.name);
}

/// Lê o arquivo, mostra um resumo e importa se o usuário confirmar.
Future<void> previewAndImport(BuildContext context, Uint8List bytes, String fileName) async {
  final state = context.read<AppState>();
  final Workout preview;
  try {
    preview = importActivity(bytes, fileName: fileName);
  } on ImportException catch (e) {
    _snack(context, e.message);
    return;
  }
  final healthReady = state.healthState == HealthState.ready;
  final save = await showDialog<bool?>(
    context: context,
    builder: (ctx) => _ImportPreviewDialog(workout: preview, canSaveToHealth: healthReady),
  );
  if (save == null || !context.mounted) return;
  try {
    final r = await state.importFile(bytes, fileName: fileName, saveToHealth: save);
    if (!context.mounted) return;
    _snack(
      context,
      r.mergedWithHealth
          ? 'Esse treino já estava no Health Connect: juntamos a rota e os detalhes do arquivo.'
          : r.savedToHealth
              ? 'Treino importado e salvo no Health Connect.'
              : 'Treino importado.',
    );
    final shown = state.workouts.firstWhere((w) => w.sameSessionAs(r.workout), orElse: () => r.workout);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutDetailScreen(workout: shown)));
  } on ImportException catch (e) {
    _snack(context, e.message);
  }
}

void _snack(BuildContext context, String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

class _ImportPreviewDialog extends StatefulWidget {
  const _ImportPreviewDialog({required this.workout, required this.canSaveToHealth});
  final Workout workout;
  final bool canSaveToHealth;

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  late bool _save = widget.canSaveToHealth;

  @override
  Widget build(BuildContext context) {
    final w = widget.workout;
    final t = Theme.of(context).textTheme;
    final rows = <(String, String)>[
      ('Tipo', w.kind.label),
      ('Data', fmtWorkoutDate(w.start)),
      ('Duração', fmtDuration(w.duration)),
      if (w.distanceKm != null) ('Distância', fmtKm(w.distanceKm, decimals: 2)),
      if (w.paceSecPerKm != null && (w.kind == WorkoutKind.corrida || w.kind == WorkoutKind.caminhada))
        ('Pace médio', fmtPace(w.paceSecPerKm)),
      if (w.avgHr != null) ('FC média', '${w.avgHr!.round()} bpm'),
      ('Origem', w.source),
      ('Detalhes', [if (w.route.isNotEmpty) 'rota', if (w.hr.length > 1) 'FC', if (w.splits.isNotEmpty) 'parciais'].join(', ').ifEmpty('só totais')),
    ];
    return AlertDialog(
      title: Text(w.title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (l, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 92, child: Text(l, style: t.bodySmall)),
              Expanded(child: Text(v, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
            ]),
          ),
        if (widget.canSaveToHealth)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _save,
            onChanged: (v) => setState(() => _save = v),
            title: const Text('Salvar também no Health Connect'),
            subtitle: const Text('Outros apps de saúde passam a ver este treino'),
          ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _save && widget.canSaveToHealth), child: const Text('Importar')),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Recebe arquivos de "Compartilhar → Fast run" (ou "Abrir com") e importa.
class ShareReceiver extends StatefulWidget {
  const ShareReceiver({super.key, required this.child});
  final Widget child;

  @override
  State<ShareReceiver> createState() => _ShareReceiverState();
}

class _ShareReceiverState extends State<ShareReceiver> {
  StreamSubscription<List<SharedMediaFile>>? _sub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || !Platform.isAndroid) return;
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(_handle, onError: (_) {});
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handle(files);
      ReceiveSharingIntent.instance.reset();
    }).catchError((_) {});
  }

  Future<void> _handle(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final f = files.first;
    // Espera a tela montar (app aberto pelo compartilhamento).
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    try {
      final file = File(f.path);
      final bytes = await file.readAsBytes();
      if (mounted) await previewAndImport(context, bytes, f.path.split('/').last);
    } catch (e) {
      if (mounted) _snack(context, 'Não foi possível ler o arquivo compartilhado: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Como fazer o relógio/app mandar os treinos para o Health Connect.
class ConnectGuideScreen extends StatelessWidget {
  const ConnectGuideScreen({super.key});

  static const _apps = <(String, List<String>)>[
    (
      'Zepp (Amazfit)',
      [
        'Abra o app Zepp e toque em Perfil.',
        'Entre em "Adicionar contas" (ou "Conectar apps").',
        'Escolha Health Connect e permita "Exercício", "Frequência cardíaca" e "Distância".',
        'Sincronize o relógio no Zepp. Os treinos novos aparecem aqui em alguns minutos.',
      ]
    ),
    (
      'Garmin Connect',
      [
        'Abra o Garmin Connect e vá em Mais → Configurações → Apps conectados.',
        'Escolha Health Connect e libere os dados de atividades.',
        'Alternativa: o Garmin Connect também exporta FIT/GPX (Atividade → ⋮ → Exportar), que dá para importar aqui.',
      ]
    ),
    (
      'Strava',
      [
        'No Strava: Você → Configurações → Aplicativos, serviços e dispositivos → Health Connect.',
        'Ative o envio de atividades.',
        'Para um treino antigo: abra a atividade no site do Strava → ⋯ → Exportar GPX, e importe o arquivo aqui.',
      ]
    ),
    (
      'Samsung Health, Google Fit e outros',
      [
        'Procure nas configurações do app a opção Health Connect (ou "Apps conectados").',
        'Libere o envio de exercícios. O nome e o caminho variam por versão.',
      ]
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Conectar relógio ou app')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(
            'O Fast run lê os treinos do Health Connect, o "cofre" de saúde do Android. Cada app (Zepp, Garmin, Strava...) '
            'precisa ser configurado para enviar os treinos para lá. Depois disso, eles aparecem aqui sozinhos, '
            'sem você levar o celular na corrida.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (state.healthState != HealthState.ready)
            Card(
              color: c.secondaryContainer,
              child: ListTile(
                title: const Text('Primeiro, libere o Fast run no Health Connect'),
                trailing: TextButton(onPressed: state.connectHealth, child: const Text('Conectar')),
              ),
            ),
          for (final (name, steps) in _apps)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: ExpansionTile(
                shape: const Border(),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, s) in steps.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 22, child: Text('${i + 1}.', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                        Expanded(child: Text(s, style: t.bodyMedium)),
                      ]),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Prefere importar um arquivo?'),
              subtitle: const Text('No app do relógio, exporte o treino (GPX, TCX ou FIT) e use "Compartilhar → Fast run", ou importe por aqui.'),
              onTap: () => pickAndImport(context),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: state.syncing ? null : state.sync,
            icon: const Icon(Icons.sync),
            label: const Text('Já configurei: buscar treinos agora'),
          ),
        ],
      ),
    );
  }
}
