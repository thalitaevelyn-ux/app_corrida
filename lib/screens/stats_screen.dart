import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/stats.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _monthly = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final st = Stats(s.workouts, now: s.now);
    final now = s.now;

    final DateTime curFrom, prevFrom;
    if (_monthly) {
      curFrom = DateTime(now.year, now.month);
      prevFrom = DateTime(now.year, now.month - 1);
    } else {
      curFrom = Stats.mondayOf(now);
      prevFrom = curFrom.subtract(const Duration(days: 7));
    }
    final cur = st.totals(curFrom, now.add(const Duration(days: 1)));
    final prev = st.totals(prevFrom, curFrom);
    final buckets = _monthly ? st.months(6) : st.weeks(8);
    final byKind = st.byKind(_monthly ? DateTime(now.year, now.month - 2) : now.subtract(const Duration(days: 28)), now.add(const Duration(days: 1)));
    final rec = st.records();
    final weekPlanKm = s.plan?.week(s.plan!.currentWeek(now))?.totalKm;

    String delta(num a, num b, String unit) {
      final d = a - b;
      if (d == 0) return 'igual ao período anterior';
      final txt = unit == 'km' ? fmtKm(d.abs().toDouble()) : '${d.abs()}';
      return '${d > 0 ? '+' : '−'}$txt vs. anterior';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Estatísticas', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('Semanas')), ButtonSegment(value: true, label: Text('Meses'))],
          selected: {_monthly},
          onSelectionChanged: (v) => setState(() => _monthly = v.first),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.7,
          children: [
            MetricCard(
              label: _monthly ? 'Km neste mês' : 'Km nesta semana',
              value: fmtKm(cur.runKm),
              note: !_monthly && weekPlanKm != null && weekPlanKm > 0 ? 'meta: ${fmtKm(weekPlanKm, decimals: 0)}' : delta(cur.runKm, prev.runKm, 'km'),
            ),
            MetricCard(label: 'Treinos', value: '${cur.count}', note: delta(cur.count, prev.count, '')),
            MetricCard(
              label: 'Pace médio (corrida)',
              value: fmtPace(cur.avgPace, unit: false),
              note: (cur.avgPace != null && prev.avgPace != null)
                  ? '${(cur.avgPace! - prev.avgPace!).round() <= 0 ? '−' : '+'}${(cur.avgPace! - prev.avgPace!).abs().round()} s/km vs. anterior'
                  : null,
            ),
            MetricCard(label: 'Tempo ativo', value: fmtDurationShort(cur.active), note: 'todos os tipos'),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text('Volume de corrida (km) · ${_monthly ? 'últimos 6 meses' : 'últimas 8 semanas'}',
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              SizedBox(height: 180, child: _VolumeChart(buckets: buckets, color: c.primary)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (byKind.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Por tipo de treino · ${_monthly ? 'últimos 3 meses' : 'últimas 4 semanas'}',
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (final e in byKind.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 88, child: Text(e.key.label, style: t.bodyMedium)),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: e.value.inSeconds / byKind.values.first.inSeconds,
                            minHeight: 10,
                            color: kindColors(context, e.key).$2,
                            backgroundColor: c.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      SizedBox(width: 64, child: Text(fmtDurationShort(e.value), textAlign: TextAlign.right, style: t.bodySmall)),
                    ]),
                  ),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Recordes (últimos 180 dias)', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              _recRow(context, 'Melhor 5 km', rec.best5k == null ? '—' : fmtDuration(rec.best5k!)),
              _recRow(context, 'Melhor 10 km', rec.best10k == null ? '—' : fmtDuration(rec.best10k!)),
              _recRow(context, 'Mais longa', fmtKm(rec.longestKm)),
              const SizedBox(height: 4),
              Text('5 e 10 km calculados pelo pace médio de corridas com pelo menos essa distância.', style: t.bodySmall),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _recRow(BuildContext context, String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [Expanded(child: Text(l)), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}

class _VolumeChart extends StatelessWidget {
  const _VolumeChart({required this.buckets, required this.color});
  final List<Bucket> buckets;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final maxKm = buckets.fold<double>(0, (m, b) => b.km > m ? b.km : m);
    return BarChart(
      BarChartData(
        maxY: maxKm == 0 ? 10 : maxKm * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, _, rod, _) => BarTooltipItem(fmtKm(rod.toY), TextStyle(color: Theme.of(context).colorScheme.onInverseSurface)),
            getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              getTitlesWidget: (v, _) => Text(buckets[v.toInt()].km.toStringAsFixed(0), style: t.labelSmall),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(buckets[v.toInt()].label, style: t.labelSmall),
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: buckets[i].km,
                width: 18,
                color: i == buckets.length - 1 ? color.withValues(alpha: 0.45) : color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ]),
        ],
      ),
    );
  }
}
