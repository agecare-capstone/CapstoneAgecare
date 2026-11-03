import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' hide Threshold;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../patients/application/patients_providers.dart';
import '../data/vitals_repository.dart';
import '../domain/models.dart';

/// Rango de días seleccionado en el detalle.
final _rangeProvider = StateProvider<int>((ref) => 7);

final _seriesProvider =
    FutureProvider.family<VitalSeries?, VitalType>((ref, type) async {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return null;
  final days = ref.watch(_rangeProvider);
  final to = DateTime.now();
  return ref.watch(vitalsRepositoryProvider).getSeries(
        patient.patientId,
        type,
        from: to.subtract(Duration(days: days)),
        to: to,
        granularity: 'day',
      );
});

/// Detalle de un vital con gráfica de tendencia y umbral (ticket AGE-304).
class VitalDetailScreen extends ConsumerWidget {
  const VitalDetailScreen({super.key, required this.typeApiValue});

  final String typeApiValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = VitalType.fromApi(typeApiValue);
    final range = ref.watch(_rangeProvider);
    final series = ref.watch(_seriesProvider(type));

    return Scaffold(
      appBar: AppBar(title: Text(type.label)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 días')),
                ButtonSegment(value: 30, label: Text('30 días')),
                ButtonSegment(value: 90, label: Text('90 días')),
              ],
              selected: {range},
              onSelectionChanged: (s) =>
                  ref.read(_rangeProvider.notifier).state = s.first,
              showSelectedIcon: false,
            ),
          ),
          Expanded(
            child: series.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(_seriesProvider(type))),
              data: (data) => data == null || data.points.isEmpty
                  ? const EmptyView(
                      icon: Icons.show_chart_rounded,
                      title: 'Sin datos en este rango')
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 24, 24),
                      child: Column(
                        children: [
                          Expanded(child: _TrendChart(series: data)),
                          if (data.points.any((p) => p.min != null && p.max != null))
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: _MinMaxLegend(),
                            ),
                          if (data.threshold != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                      width: 18, height: 3,
                                      color: AppColors.statusAttention),
                                  const SizedBox(width: 6),
                                  Text(
                                    _thresholdLabel(data.threshold!, type),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _thresholdLabel(Threshold t, VitalType type) {
    final parts = <String>[];
    if (t.minValue != null) parts.add('mín ${t.minValue!.toStringAsFixed(0)}');
    if (t.maxValue != null) parts.add('máx ${t.maxValue!.toStringAsFixed(0)}');
    return 'Umbral de alerta: ${parts.join(' · ')} ${type.unit}';
  }
}

/// Leyenda de las lineas punteadas de minimo/maximo diario del grafico
/// (AGE-304 / AC: "...mostrando minimos y maximos").
class _MinMaxLegend extends StatelessWidget {
  const _MinMaxLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++) ...[
          Container(width: 5, height: 2, color: AppColors.textSecondary.withValues(alpha: .6)),
          if (i < 2) const SizedBox(width: 3),
        ],
        const SizedBox(width: 6),
        const Text(
          'Líneas punteadas: mínimo y máximo del día',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.series});

  final VitalSeries series;

  @override
  Widget build(BuildContext context) {
    final points = series.points;
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value)
    ];

    final hasMinMax = points.any((p) => p.min != null && p.max != null);
    final minSpots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        if (points[i].min != null) FlSpot(i.toDouble(), points[i].min!)
    ];
    final maxSpots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        if (points[i].max != null) FlSpot(i.toDouble(), points[i].max!)
    ];

    final values = points.map((p) => p.value);
    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    for (final p in points) {
      if (p.min != null && p.min! < minY) minY = p.min!;
      if (p.max != null && p.max! > maxY) maxY = p.max!;
    }
    final t = series.threshold;
    if (t?.minValue != null && t!.minValue! < minY) minY = t.minValue!;
    if (t?.maxValue != null && t!.maxValue! > maxY) maxY = t.maxValue!;
    final pad = (maxY - minY) * .15 + 1;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              const FlLine(color: AppColors.divider, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 42),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (points.length / 4).ceilToDouble().clamp(1, 999),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('d/M').format(points[i].ts),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          if (t?.minValue != null)
            HorizontalLine(
                y: t!.minValue!,
                color: AppColors.statusAttention,
                strokeWidth: 1.5,
                dashArray: [6, 4]),
          if (t?.maxValue != null)
            HorizontalLine(
                y: t!.maxValue!,
                color: AppColors.statusAttention,
                strokeWidth: 1.5,
                dashArray: [6, 4]),
        ]),
        lineBarsData: [
          if (hasMinMax) ...[
            LineChartBarData(
              spots: minSpots,
              isCurved: true,
              curveSmoothness: .25,
              color: AppColors.textSecondary.withValues(alpha: .6),
              barWidth: 1,
              dotData: const FlDotData(show: false),
              dashArray: [4, 3],
            ),
            LineChartBarData(
              spots: maxSpots,
              isCurved: true,
              curveSmoothness: .25,
              color: AppColors.textSecondary.withValues(alpha: .6),
              barWidth: 1,
              dotData: const FlDotData(show: false),
              dashArray: [4, 3],
            ),
          ],
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: .25,
            color: AppColors.primary,
            barWidth: 3,
            dotData: FlDotData(show: points.length <= 14),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withValues(alpha: .08),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched
                .map((s) => LineTooltipItem(
                      '${points[s.spotIndex].value} ${series.type.unit}\n${DateFormat('d MMM', 'es').format(points[s.spotIndex].ts)}',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}
