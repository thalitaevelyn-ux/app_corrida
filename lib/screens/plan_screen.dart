import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/plan_api.dart';
import '../services/plan_progress.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import 'onboarding_screen.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  int? _week;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final plan = s.plan!;
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final current = plan.currentWeek(s.now);
    final sel = (_week ?? current).clamp(1, plan.totalWeeks);
    final week = plan.week(sel)!;
    final items = s.progress!.week(sel, now: s.now);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Row(children: [
          Expanded(child: Text('Meu plano', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnboardingScreen(initial: s.goal))),
            child: const Text('Mudar objetivo'),
          ),
        ]),
        const SizedBox(height: 12),
        Card(
          color: c.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${plan.source == 'ia' ? 'Gerado pela IA' : 'Plano por regras'} · atualizado ${DateFormat('dd/MM').format(plan.updatedAt)}',
                style: t.labelMedium?.copyWith(color: c.onTertiaryContainer, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(plan.summary, style: t.bodyMedium?.copyWith(color: c.onTertiaryContainer)),
              const SizedBox(height: 8),
              Text('Nível: ${plan.estimatedLevel}', style: t.bodySmall?.copyWith(color: c.onTertiaryContainer)),
              if (!PlanApiConfig.enabled) ...[
                const SizedBox(height: 8),
                Text('A IA não está configurada neste build; o plano usa regras de treino.',
                    style: t.bodySmall?.copyWith(color: c.onTertiaryContainer)),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Seus ritmos de treino', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _pace('Leve', plan.paces.easy),
              _pace('Longão', plan.paces.long),
              _pace('Limiar (tempo run)', plan.paces.threshold),
              _pace('Intervalado', plan.paces.interval),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: plan.totalWeeks,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text(i + 1 == current ? 'Sem ${i + 1} · atual' : 'Sem ${i + 1}'),
              selected: sel == i + 1,
              onSelected: (_) => setState(() => _week = i + 1),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('${week.focus} · ${fmtKm(week.totalKm, decimals: 0)} previstos', style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
        const SizedBox(height: 8),
        for (final p in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  SizedBox(
                    width: 48,
                    child: Column(children: [
                      Text(weekdayShort[p.session.weekday - 1], style: t.bodySmall),
                      Text('${p.date.day}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.session.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(p.session.description, style: t.bodySmall),
                      if (p.session.targetPace != null) Text('Pace: ${p.session.targetPace}', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  _StatusTag(p.status),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Como está se sentindo esta semana?', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Isso entra no ajuste do plano no início da próxima semana.', style: t.bodySmall),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: 'cansado', label: Text('Cansado')),
                  ButtonSegment(value: 'normal', label: Text('Normal')),
                  ButtonSegment(value: 'otimo', label: Text('Ótimo')),
                ],
                selected: {if (s.feeling != null) s.feeling!},
                onSelectionChanged: (v) {
                  if (v.isNotEmpty) s.setFeeling(v.first);
                },
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: s.generating
              ? null
              : () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Gerar o plano de novo?'),
                      content: const Text('O plano atual será substituído por um novo, com base nos treinos de agora.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gerar')),
                      ],
                    ),
                  );
                  if (ok == true) await s.generatePlan();
                },
          icon: s.generating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
          label: const Text('Gerar plano de novo'),
        ),
      ],
    );
  }

  Widget _pace(String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Expanded(child: Text(l)), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}

class _StatusTag extends StatelessWidget {
  const _StatusTag(this.status);
  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (status) {
      SessionStatus.done => ('Feito', c.primaryContainer, c.onPrimaryContainer),
      SessionStatus.today => ('Hoje', c.primary, c.onPrimary),
      SessionStatus.missed => ('Perdido', c.errorContainer, c.onErrorContainer),
      SessionStatus.upcoming => ('Previsto', c.surfaceContainerHighest, c.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
