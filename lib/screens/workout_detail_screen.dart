import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/plan.dart';
import '../models/workout.dart';
import '../services/plan_progress.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class WorkoutDetailScreen extends StatefulWidget {
  const WorkoutDetailScreen({super.key, required this.workout});
  final Workout workout;

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AppState>().loadDetail(widget.workout);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final w = widget.workout;
    final t = Theme.of(context).textTheme;
    final isFoot = w.kind == WorkoutKind.corrida || w.kind == WorkoutKind.caminhada;
    final planned = _plannedFor(s, w);

    final metrics = <(String, String)>[
      if (w.distanceKm != null) ('Distância', fmtKm(w.distanceKm, decimals: 2)),
      ('Duração', fmtDuration(w.duration)),
      if (isFoot && w.paceSecPerKm != null) ('Pace médio', fmtPace(w.paceSecPerKm)),
      if (!isFoot && w.speedKmh != null) ('Velocidade', '${w.speedKmh!.toStringAsFixed(1).replaceAll('.', ',')} km/h'),
      if (w.avgHr != null) ('FC média', '${w.avgHr!.round()} bpm'),
      if (w.hr.isNotEmpty) ('FC máxima', '${w.hr.map((h) => h.bpm).reduce(math.max).round()} bpm'),
      if (w.kcal != null && w.kcal! > 0) ('Calorias', '${w.kcal} kcal'),
      if (w.steps != null && w.steps! > 0) ('Passos', NumberFormat.decimalPattern('pt_BR').format(w.steps)),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(w.kind.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(w.title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text('${DateFormat("EEEE, d 'de' MMMM, HH:mm", 'pt_BR').format(w.start)} · ${w.source}', style: t.bodyMedium),
          const SizedBox(height: 16),
          if (w.route.length >= 2) ...[
            _RouteView(points: w.route),
            const SizedBox(height: 12),
          ],
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.25,
            children: [for (final (l, v) in metrics) MetricCard(label: l, value: v)],
          ),
          if (planned != null) ...[
            const SizedBox(height: 12),
            _PlanComparison(session: planned, workout: w),
          ],
          if (w.hr.isNotEmpty) ...[
            const SizedBox(height: 12),
            _HrZones(samples: w.hr, maxHr: s.goal?.maxHr ?? 190),
          ],
          if (w.splits.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Parciais por km', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final sp in w.splits)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        SizedBox(width: 56, child: Text('km ${sp.km}', style: t.bodyMedium)),
                        Expanded(child: Text(fmtPace(sp.duration.inSeconds.toDouble()), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                        if (sp.avgHr != null) Text('${sp.avgHr!.round()} bpm', style: t.bodySmall),
                      ]),
                    ),
                ]),
              ),
            ),
          ],
          if (w.hr.isEmpty && w.splits.isEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Sem dados de frequência cardíaca para este treino. Eles aparecem quando o relógio grava a FC no Health Connect.',
              style: t.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  PlanSession? _plannedFor(AppState s, Workout w) {
    final plan = s.plan;
    if (plan == null) return null;
    final prog = PlanProgress(plan, s.workouts);
    for (var n = 1; n <= plan.totalWeeks; n++) {
      for (final p in prog.week(n, now: s.now)) {
        if (p.workout?.id == w.id) return p.session;
      }
    }
    return null;
  }
}

class _PlanComparison extends StatelessWidget {
  const _PlanComparison({required this.session, required this.workout});
  final PlanSession session;
  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final parts = <String>['Planejado: ${session.title}'];
    if (session.targetPace != null) parts.add('pace-alvo ${session.targetPace}');
    if (workout.paceSecPerKm != null) parts.add('você fez ${fmtPace(workout.paceSecPerKm)}');
    if (session.distanceKm != null && workout.distanceKm != null) {
      parts.add('${fmtKm(workout.distanceKm)} de ${fmtKm(session.distanceKm)}');
    }
    return Card(
      color: c.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.check_circle, color: c.onPrimaryContainer),
        title: Text('Treino do plano', style: TextStyle(color: c.onPrimaryContainer, fontWeight: FontWeight.w600)),
        subtitle: Text(parts.join(' · '), style: TextStyle(color: c.onPrimaryContainer)),
      ),
    );
  }
}

class _HrZones extends StatelessWidget {
  const _HrZones({required this.samples, required this.maxHr});
  final List<HrSample> samples;
  final int maxHr;

  static const _colors = [Color(0xFF9CA3AF), Color(0xFF3B82F6), Color(0xFF22C55E), Color(0xFFF59E0B), Color(0xFFDC2626)];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // Tempo em cada zona: cada amostra vale o intervalo até a próxima (máx. 60 s).
    final secs = List<double>.filled(5, 0);
    for (var i = 0; i < samples.length; i++) {
      final dt = i + 1 < samples.length ? samples[i + 1].time.difference(samples[i].time).inSeconds.clamp(1, 60) : 5;
      final pct = samples[i].bpm / maxHr;
      final z = pct < 0.6 ? 0 : pct < 0.7 ? 1 : pct < 0.8 ? 2 : pct < 0.9 ? 3 : 4;
      secs[z] += dt;
    }
    final total = secs.reduce((a, b) => a + b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Zonas de frequência cardíaca', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          Text('FC máx. estimada: $maxHr bpm', style: t.bodySmall),
          const SizedBox(height: 8),
          for (var z = 0; z < 5; z++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 28, child: Text('Z${z + 1}', style: t.labelMedium)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : secs[z] / total,
                      minHeight: 10,
                      color: _colors[z],
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                SizedBox(width: 56, child: Text('${(secs[z] / 60).round()} min', textAlign: TextAlign.right, style: t.bodySmall)),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Desenho simples da rota (sem mapa, para não depender de chave de API).
class _RouteView extends StatelessWidget {
  const _RouteView({required this.points});
  final List<RoutePoint> points;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Desenho da rota',
      child: Container(
        height: 180,
        decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
        child: CustomPaint(painter: _RoutePainter(points, c.primary), size: Size.infinite),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.points, this.color);
  final List<RoutePoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lats = points.map((p) => p.lat), lngs = points.map((p) => p.lng);
    final minLat = lats.reduce(math.min), maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min), maxLng = lngs.reduce(math.max);
    final latC = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final w = (maxLng - minLng) * latC, h = maxLat - minLat;
    const pad = 20.0;
    final scale = math.min((size.width - 2 * pad) / (w == 0 ? 1e-9 : w), (size.height - 2 * pad) / (h == 0 ? 1e-9 : h));
    final ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2;
    Offset map(RoutePoint p) => Offset(ox + (p.lng - minLng) * latC * scale, oy + (maxLat - p.lat) * scale);

    final path = Path()..moveTo(map(points.first).dx, map(points.first).dy);
    for (final p in points.skip(1)) {
      final o = map(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(map(points.first), 6, Paint()..color = const Color(0xFF1B5E33));
    canvas.drawCircle(map(points.last), 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.points != points;
}
