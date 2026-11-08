import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/workout.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'workout_detail_screen.dart';

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({super.key});

  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
  WorkoutKind? _filter;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final list = s.filtered(_filter);
    final sources = s.workouts.map((w) => w.source).toSet().take(3).join(', ');

    return RefreshIndicator(
      onRefresh: s.sync,
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverList.list(children: [
            Text('Treinos', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(sources.isEmpty ? 'Importados do Health Connect' : 'Importados do Health Connect · $sources', style: t.bodySmall),
            const SizedBox(height: 12),
            HealthConnectBanner(state: s),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: const Text('Todos'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
              for (final k in WorkoutKind.values.where((k) => k != WorkoutKind.outro || s.workouts.any((w) => w.kind == k)))
                ChoiceChip(label: Text(k.label), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
            ]),
          ]),
        ),
        if (list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(s.syncing ? 'Carregando…' : 'Nenhum treino encontrado.', style: t.bodyMedium)),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            sliver: SliverList.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => WorkoutTile(
                workout: list[i],
                showSource: true,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutDetailScreen(workout: list[i]))),
              ),
            ),
          ),
      ]),
    );
  }
}
