import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/plan.dart';
import '../services/plan_progress.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'workout_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final plan = s.plan!;
    final goal = s.goal!;
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final now = s.now;
    final weekN = plan.currentWeek(now);
    final started = !now.isBefore(plan.startDate);
    final week = s.progress!.week(weekN, now: now);
    final next = s.progress!.next(now: now);
    final hour = now.hour;
    final hello = hour < 12 ? 'Bom dia!' : (hour < 18 ? 'Boa tarde!' : 'Boa noite!');

    return RefreshIndicator(
      onRefresh: s.sync,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(toBeginningOfSentenceCase(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(now)), style: t.bodySmall),
                Text(hello, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
            IconButton.outlined(
              tooltip: 'Sincronizar com o Health Connect',
              onPressed: s.syncing ? null : s.sync,
              icon: s.syncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
            ),
          ]),
          const SizedBox(height: 12),
          HealthConnectBanner(state: s),
          const SizedBox(height: 12),

          // Objetivo e progresso.
          Card(
            color: c.primary,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Seu objetivo', style: t.bodySmall?.copyWith(color: c.onPrimary)),
                      Text(goal.shortTitle, style: t.titleLarge?.copyWith(color: c.onPrimary, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  Chip(
                    label: Text(started ? 'Semana $weekN de ${plan.totalWeeks}' : 'Começa ${DateFormat('dd/MM').format(plan.startDate)}'),
                    side: BorderSide.none,
                  ),
                ]),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: started ? weekN / plan.totalWeeks : 0,
                    minHeight: 8,
                    color: c.onPrimary,
                    backgroundColor: c.onPrimary.withValues(alpha: 0.3),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          if (started) _WeekStrip(items: week, now: now),
          const SizedBox(height: 12),

          if (next != null) _NextSession(p: next, now: now),
          const SizedBox(height: 12),

          if (plan.adjustmentNote != null)
            Card(
              color: c.tertiaryContainer,
              child: ListTile(
                leading: Icon(Icons.auto_awesome, color: c.onTertiaryContainer),
                title: Text(plan.source == 'ia' ? 'Ajuste da IA para esta semana' : 'Ajuste da semana',
                    style: TextStyle(color: c.onTertiaryContainer, fontWeight: FontWeight.w600)),
                subtitle: Text(plan.adjustmentNote!, style: TextStyle(color: c.onTertiaryContainer)),
              ),
            ),

          SectionTitle('Últimos treinos'),
          if (s.workouts.isEmpty)
            Text(
              s.healthState == HealthState.ready ? 'Nenhum treino nos últimos 180 dias.' : 'Conecte o Health Connect para ver seus treinos.',
              style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
            ),
          for (final w in s.workouts.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: WorkoutTile(
                workout: w,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutDetailScreen(workout: w))),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.items, required this.now});
  final List<SessionProgress> items;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final byDay = {for (final p in items) p.session.weekday: p};
    return Row(children: [
      for (var d = 1; d <= 7; d++)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Builder(builder: (context) {
              final p = byDay[d];
              final isToday = now.weekday == d;
              final Color bg;
              final Color fg;
              IconData? icon;
              if (p == null) {
                bg = c.surface;
                fg = c.onSurfaceVariant;
              } else if (p.status == SessionStatus.done) {
                bg = c.primaryContainer;
                fg = c.onPrimaryContainer;
                icon = Icons.check;
              } else if (p.status == SessionStatus.missed) {
                bg = c.surfaceContainerHighest;
                fg = c.onSurfaceVariant;
                icon = Icons.close;
              } else {
                bg = isToday ? c.primary : c.surface;
                fg = isToday ? c.onPrimary : c.onSurface;
              }
              final label = p == null
                  ? '—'
                  : p.session.distanceKm != null
                      ? p.session.distanceKm!.toStringAsFixed(p.session.distanceKm! % 1 == 0 ? 0 : 1)
                      : p.session.type == SessionType.forca
                          ? 'Força'
                          : '${p.session.durationMin ?? ''}′';
              return Semantics(
                label: '${weekdayShort[d - 1]}: ${p?.session.title ?? 'descanso'}, ${p?.status.name ?? ''}',
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isToday ? c.primary : c.outlineVariant),
                  ),
                  child: Column(children: [
                    Text(weekdayShort[d - 1].substring(0, 1), style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(height: 4),
                    icon != null ? Icon(icon, size: 16, color: fg) : Text(label, style: TextStyle(color: fg, fontSize: 12)),
                  ]),
                ),
              );
            }),
          ),
        ),
    ]);
  }
}

class _NextSession extends StatelessWidget {
  const _NextSession({required this.p, required this.now});
  final SessionProgress p;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final isToday = p.status == SessionStatus.today;
    final when = isToday
        ? 'TREINO DE HOJE'
        : 'PRÓXIMO: ${DateFormat('EEEE, dd/MM', 'pt_BR').format(p.date).toUpperCase()}';
    final s = p.session;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(when, style: t.labelMedium?.copyWith(color: c.primary, fontWeight: FontWeight.w700))),
            if (s.durationMin != null) Text('~${s.durationMin} min', style: t.bodySmall),
          ]),
          const SizedBox(height: 6),
          Text(s.title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(s.description, style: t.bodyMedium),
          if (s.targetPace != null) ...[
            const SizedBox(height: 6),
            Text('Pace-alvo: ${s.targetPace}', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
          if (isToday && s.type.isRun) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Shell.openRecord(context),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Iniciar treino'),
            ),
          ],
        ]),
      ),
    );
  }
}
