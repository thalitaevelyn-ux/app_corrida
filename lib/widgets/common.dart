import 'package:flutter/material.dart';

import '../models/workout.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';

class WorkoutTile extends StatelessWidget {
  const WorkoutTile({super.key, required this.workout, required this.onTap, this.showSource = false});
  final Workout workout;
  final VoidCallback onTap;
  final bool showSource;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = kindColors(context, workout.kind);
    final t = Theme.of(context).textTheme;
    final main = workout.distanceKm != null ? fmtKm(workout.distanceKm) : fmtDurationShort(workout.duration);
    final sub = fmtWorkoutDate(workout.start) + (showSource ? ' · ${workout.source}' : '');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: Icon(kindIcon(workout.kind), color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(workout.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub, style: t.bodySmall, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(main, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              if (workout.distanceKm != null) Text(fmtDuration(workout.duration), style: t.bodySmall),
            ]),
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          ?trailing,
        ]),
      );
}

/// Cartão com uma métrica (rótulo pequeno + valor).
class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value, this.note});
  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: t.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(note!, style: t.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ],
        ]),
      ),
    );
  }
}

/// Aviso para conectar o Health Connect, mostrado onde faltam dados.
class HealthConnectBanner extends StatelessWidget {
  const HealthConnectBanner({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final String text;
    final String? action;
    switch (state.healthState) {
      case HealthState.ready:
      case HealthState.unknown:
        return const SizedBox.shrink();
      case HealthState.unavailable:
        text = 'Health Connect não está disponível neste aparelho. Os treinos não serão lidos.';
        action = null;
      case HealthState.needsInstall:
        text = 'Instale ou atualize o Health Connect para importar seus treinos.';
        action = 'Abrir Play Store';
      case HealthState.needsPermission:
        text = 'Permita o acesso ao Health Connect para ler seus treinos e personalizar o plano.';
        action = 'Conectar';
    }
    final c = Theme.of(context).colorScheme;
    return Card(
      color: c.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.favorite_outline, color: c.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: c.onSecondaryContainer))),
          if (action != null) TextButton(onPressed: state.connectHealth, child: Text(action)),
        ]),
      ),
    );
  }
}
