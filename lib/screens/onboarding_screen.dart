import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/goal.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Escolha do objetivo. Também é aberta pelo botão "Mudar objetivo" do plano.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.initial});
  final Goal? initial;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  late GoalType _type;
  late double _distance;
  late int _days;
  DateTime? _raceDate;
  final _time = TextEditingController();
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _baseKm = TextEditingController();

  static final _distances = <double, String>{5: '5 km', 10: '10 km', 21.1: 'Meia (21 km)', 42.2: 'Maratona'};

  @override
  void initState() {
    super.initState();
    final g = widget.initial;
    _type = g?.type ?? GoalType.distancia;
    _distance = (g != null && _distances.containsKey(g.distanceKm)) ? g.distanceKm : 10;
    _days = g?.daysPerWeek ?? 4;
    _raceDate = g?.raceDate;
    if (g?.targetTime != null) _time.text = fmtDuration(g!.targetTime!);
    if (g?.age != null) _age.text = '${g!.age}';
    if (g?.weightKg != null) _weight.text = g!.weightKg!.toStringAsFixed(0);
    _baseKm.text = g?.type == GoalType.base ? g!.distanceKm.toStringAsFixed(0) : '25';
  }

  @override
  void dispose() {
    for (final c in [_time, _age, _weight, _baseKm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final state = context.read<AppState>();
    final goal = Goal(
      type: _type,
      distanceKm: switch (_type) {
        GoalType.sofa5k => 5,
        GoalType.base => double.parse(_baseKm.text.replaceAll(',', '.')),
        _ => _distance,
      },
      daysPerWeek: _type == GoalType.sofa5k ? _days.clamp(3, 4) : _days,
      targetTime: _type == GoalType.tempo ? parseDuration(_time.text) : null,
      raceDate: (_type == GoalType.distancia || _type == GoalType.tempo) ? _raceDate : null,
      age: int.tryParse(_age.text),
      weightKg: double.tryParse(_weight.text.replaceAll(',', '.')),
    );
    await state.setGoal(goal);
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final fit = state.fitness;

    return Scaffold(
      appBar: widget.initial == null ? null : AppBar(title: const Text('Mudar objetivo')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              if (widget.initial == null) ...[
                Text('Qual é o seu objetivo?', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'Montamos um plano a partir do seu histórico no Health Connect e ajustamos toda semana.',
                  style: t.bodyLarge?.copyWith(color: c.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
              ],
              if (state.healthState == HealthState.ready)
                Card(
                  color: c.primaryContainer,
                  child: ListTile(
                    leading: Icon(Icons.favorite, color: c.onPrimaryContainer),
                    title: Text(state.syncing ? 'Lendo seus treinos…' : fit.describe(),
                        style: TextStyle(color: c.onPrimaryContainer)),
                    subtitle: Text('Nível estimado: ${fit.levelLabel}', style: TextStyle(color: c.onPrimaryContainer)),
                  ),
                )
              else
                HealthConnectBanner(state: state),
              const SizedBox(height: 16),
              RadioGroup<GoalType>(
                groupValue: _type,
                onChanged: (v) => setState(() => _type = v!),
                child: Column(children: [
                  for (final g in GoalType.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        color: g == _type ? c.primaryContainer : null,
                        child: RadioListTile<GoalType>(
                          value: g,
                          title: Text(g.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(g.description),
                          controlAffinity: ListTileControlAffinity.trailing,
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              ..._details(context),
              const SizedBox(height: 16),
              Text('Dias de treino por semana', style: t.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: [
                  for (final d in (_type == GoalType.sofa5k ? [3, 4] : [3, 4, 5, 6])) ButtonSegment(value: d, label: Text('$d')),
                ],
                selected: {_type == GoalType.sofa5k ? _days.clamp(3, 4) : _days},
                onSelectionChanged: (s) => setState(() => _days = s.first),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _age,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Idade', helperText: 'Para zonas de FC', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _weight,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Peso (kg)', helperText: 'Para calorias', border: OutlineInputBorder()),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: state.generating ? null : _submit,
                icon: state.generating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: Text(state.generating ? 'Gerando plano…' : 'Gerar meu plano'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _details(BuildContext context) {
    switch (_type) {
      case GoalType.sofa5k:
        return const [];
      case GoalType.base:
        return [
          TextFormField(
            controller: _baseKm,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Volume semanal desejado (km)', border: OutlineInputBorder()),
            validator: (v) {
              final n = double.tryParse((v ?? '').replaceAll(',', '.'));
              return (n == null || n < 5 || n > 120) ? 'Informe entre 5 e 120 km' : null;
            },
          ),
        ];
      case GoalType.distancia:
      case GoalType.tempo:
        return [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _distances.entries)
              ChoiceChip(label: Text(e.value), selected: _distance == e.key, onSelected: (_) => setState(() => _distance = e.key)),
          ]),
          const SizedBox(height: 12),
          if (_type == GoalType.tempo) ...[
            TextFormField(
              controller: _time,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(labelText: 'Tempo-alvo', hintText: 'ex.: 55:00 ou 1:59:00', border: OutlineInputBorder()),
              validator: (v) => parseDuration(v ?? '') == null ? 'Use mm:ss ou h:mm:ss' : null,
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                firstDate: now.add(const Duration(days: 21)),
                lastDate: now.add(const Duration(days: 365)),
                initialDate: _raceDate ?? now.add(const Duration(days: 84)),
              );
              if (d != null) setState(() => _raceDate = d);
            },
            icon: const Icon(Icons.event),
            label: Text(_raceDate == null
                ? 'Data da prova (opcional)'
                : 'Prova em ${DateFormat('dd/MM/yyyy', 'pt_BR').format(_raceDate!)}'),
          ),
        ];
    }
  }
}
