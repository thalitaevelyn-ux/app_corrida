import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../models/workout.dart';
import '../services/plan_progress.dart';
import '../services/run_recorder.dart';
import '../state/app_state.dart';
import '../utils/format.dart';

/// Gravação de corrida com GPS. Ao finalizar, salva no Health Connect.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final _rec = RunRecorder();
  GpsPermission? _perm;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final p = await RunRecorder.ensurePermission();
    if (mounted) setState(() => _perm = p);
  }

  @override
  void dispose() {
    _rec.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_rec.running) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar corrida?'),
        content: const Text('A gravação em andamento será perdida.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuar gravando')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Descartar')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _finish() async {
    final tr = _rec.tracker;
    if (tr.distanceM < 100) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Corrida muito curta para salvar (menos de 100 m).')));
      return;
    }
    setState(() => _saving = true);
    final end = DateTime.now();
    await _rec.stop();
    if (!mounted) return;
    final state = context.read<AppState>();
    final start = tr.startedAt!;
    final kcal = tr.kcal(state.goal?.weightKg ?? 70);
    final route = _rec.routeForHealth();
    final ok = await state.saveRecordedRun(
      start: start,
      end: end,
      distanceM: tr.distanceM,
      kcal: kcal,
      splits: List.of(tr.splits),
      route: [for (final p in tr.points) RoutePoint(p.lat, p.lng)],
      writeToHealth: () => state.health.writeRun(
        start: start,
        end: end,
        distanceM: tr.distanceM,
        kcal: kcal,
        title: 'Corrida',
        route: route,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Corrida salva no Health Connect · ${fmtKm(tr.distanceM / 1000, decimals: 2)}' : 'Corrida salva no app.'),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final next = state.progress?.next(now: state.now);
    final todaySession = next?.status == SessionStatus.today ? next!.session : null;

    return PopScope(
      canPop: !_rec.running,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          await _rec.stop();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Theme(
        data: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB33F0B), brightness: Brightness.dark)),
        child: Builder(builder: (context) {
          final c = Theme.of(context).colorScheme;
          return Scaffold(
            appBar: AppBar(title: Text(todaySession?.title ?? 'Corrida livre')),
            body: SafeArea(
              child: switch (_perm) {
                null => const Center(child: CircularProgressIndicator()),
                GpsPermission.granted => ListenableBuilder(listenable: _rec, builder: (context, _) => _body(context, c, todaySession?.description)),
                _ => _permissionHelp(context),
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _body(BuildContext context, ColorScheme c, String? workoutDescription) {
    final t = Theme.of(context).textTheme;
    final tr = _rec.tracker;
    final now = DateTime.now();
    final gpsOk = tr.points.isNotEmpty && tr.points.last.accuracy <= 15;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        if (workoutDescription != null)
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(workoutDescription, style: t.bodyMedium))),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.circle, size: 10, color: !_rec.running ? c.outline : (gpsOk ? const Color(0xFF4ADE80) : const Color(0xFFF59E0B))),
          const SizedBox(width: 6),
          Text(!_rec.running ? 'Pronto para começar' : (tr.paused ? 'Pausado' : (gpsOk ? 'GPS forte · gravando' : 'Procurando GPS…'))),
        ]),
        const Spacer(),
        Text(fmtDuration(tr.elapsed(now)),
            style: t.displayLarge?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
        Text('Tempo', style: t.bodySmall),
        const SizedBox(height: 28),
        Row(children: [
          _big(context, (tr.distanceM / 1000).toStringAsFixed(2).replaceAll('.', ','), 'km'),
          _big(context, fmtPace(tr.currentPace(), unit: false), 'pace atual'),
          _big(context, fmtPace(tr.avgPace(now), unit: false), 'pace médio'),
        ]),
        if (tr.splits.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Último km: ${fmtPace(tr.splits.last.duration.inSeconds.toDouble())}', style: t.titleMedium),
        ],
        const Spacer(),
        if (!_rec.running)
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
            onPressed: () => setState(_rec.start),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Começar'),
          )
        else
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                onPressed: _saving ? null : _rec.togglePause,
                child: Text(tr.paused ? 'Retomar' : 'Pausar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                onPressed: _saving ? null : _finish,
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Finalizar e salvar'),
              ),
            ),
          ]),
      ]),
    );
  }

  Widget _big(BuildContext context, String value, String label) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(children: [
        Text(value, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
        Text(label, style: t.bodySmall),
      ]),
    );
  }

  Widget _permissionHelp(BuildContext context) {
    final (text, action, onTap) = switch (_perm!) {
      GpsPermission.serviceOff => ('A localização do aparelho está desligada.', 'Abrir configurações', Geolocator.openLocationSettings),
      GpsPermission.deniedForever => (
          'O acesso à localização foi negado. Libere nas configurações do app para gravar corridas.',
          'Abrir configurações',
          Geolocator.openAppSettings,
        ),
      _ => ('Precisamos da localização para medir distância e pace.', 'Permitir', () async => true),
    };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.location_off, size: 48),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await onTap();
            await _checkPermission();
          },
          child: Text(action),
        ),
      ]),
    );
  }
}
