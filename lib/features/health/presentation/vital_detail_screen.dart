import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' hide Threshold;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../patients/application/patients_providers.dart';
import '../data/vitals_repository.dart';
import '../domain/models.dart';
import 'health_screen.dart' show latestVitalsProvider;

/// Rango seleccionado en el detalle: 1 = hoy, o 7 / 30 / 90 días.
final _rangeProvider = StateProvider<int>((ref) => 7);

/// Agrupación según el rango: hoy cada lectura, 7 días por hora (se ve el uso
/// real del reloj aunque sea de un solo día) y 30/90 días por día.
String granularityFor(int days) => days <= 1 ? 'raw' : (days <= 7 ? 'hour' : 'day');

final _seriesProvider =
    FutureProvider.autoDispose.family<VitalSeries?, VitalType>((ref, type) async {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return null;
  // Cuando llegan lecturas nuevas del reloj (sincronización cada 10 s), se
  // recarga también el gráfico.
  ref.watch(latestVitalsProvider);
  final days = ref.watch(_rangeProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return ref.watch(vitalsRepositoryProvider).getSeries(
        patient.patientId,
        type,
        from: days <= 1 ? today : now.subtract(Duration(days: days)),
        to: now,
        granularity: granularityFor(days),
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
    final granularity = granularityFor(range);

    return Scaffold(
      appBar: AppBar(title: Text(type.label)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Hoy')),
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
              // Al recargar por datos nuevos se mantiene el gráfico en pantalla.
              skipLoadingOnReload: true,
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
                          Text(
                            _summary(data, granularity),
                            key: const Key('series-summary'),
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                              child: _TrendChart(series: data, granularity: granularity)),
                          if (data.points.any((p) => p.min != null && p.max != null))
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _MinMaxLegend(
                                  period: granularity == 'hour' ? 'de cada hora' : 'del día'),
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

  /// "51 lecturas hoy" / "2 horas con datos" / "1 día con datos".
  static String _summary(VitalSeries data, String granularity) {
    final n = data.points.length;
    return switch (granularity) {
      'raw' => '$n ${n == 1 ? 'lectura' : 'lecturas'} hoy',
      'hour' => '$n ${n == 1 ? 'hora' : 'horas'} con datos en los últimos 7 días',
      _ => '$n ${n == 1 ? 'día' : 'días'} con datos',
    };
  }

  String _thresholdLabel(Threshold t, VitalType type) {
    final parts = <String>[];
    if (t.minValue != null) parts.add('mín ${t.minValue!.toStringAsFixed(0)}');
    if (t.maxValue != null) parts.add('máx ${t.maxValue!.toStringAsFixed(0)}');
    return 'Umbral de alerta: ${parts.join(' · ')} ${type.unit}';
  }
}

/// Leyenda de las lineas punteadas de minimo/maximo del grafico
/// (AGE-304 / AC: "...mostrando minimos y maximos").
class _MinMaxLegend extends StatelessWidget {
  const _MinMaxLegend({required this.period});

  final String period;

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
        Flexible(
          child: Text(
            'Líneas punteadas: mínimo y máximo $period',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.series, required this.granularity});

  final VitalSeries series;
  final String granularity;

  /// Etiquetas en hora local: hoy "19:45", 7 días "20/11 19h", 30/90 días "20/11".
  String _label(DateTime ts) {
    final local = ts.toLocal();
    return switch (granularity) {
      'raw' => DateFormat('HH:mm').format(local),
      'hour' => '${DateFormat('d/M').format(local)} ${local.hour}h',
      _ => DateFormat('d/M').format(local),
    };
  }

  String _tooltipDate(DateTime ts) {
    final local = ts.toLocal();
    return switch (granularity) {
      'raw' => DateFormat('HH:mm').format(local),
      'hour' => DateFormat("d MMM, HH':00'", 'es').format(local),
      _ => DateFormat('d MMM', 'es').format(local),
    };
  }

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
        // Con un solo punto (p. ej. un día con datos) queda centrado y visible.
        minX: points.length == 1 ? -1 : 0,
        maxX: points.length == 1 ? 1 : (points.length - 1).toDouble(),
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
                if (value != i || i < 0 || i >= points.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_label(points[i].ts),
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
                      '${points[s.spotIndex].value.round()} ${series.type.unit}\n${_tooltipDate(points[s.spotIndex].ts)}',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}
