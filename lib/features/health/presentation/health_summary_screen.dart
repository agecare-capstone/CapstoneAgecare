import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../medications/data/medications_repository.dart';
import '../../patients/application/patients_providers.dart';
import '../data/vitals_repository.dart';
import '../domain/models.dart';

/// Métricas de un período (promedio, mínimo y máximo de un vital).
class PeriodStat {
  const PeriodStat({this.avg, this.min, this.max, this.days = 0});

  final double? avg;
  final double? min;
  final double? max;

  /// Días con al menos una lectura.
  final int days;

  bool get hasData => avg != null;

  static PeriodStat of(VitalSeries series) {
    final pts = series.points;
    if (pts.isEmpty) return const PeriodStat();
    final values = pts.map((p) => p.value).toList();
    final lows = pts.map((p) => p.min ?? p.value);
    final highs = pts.map((p) => p.max ?? p.value);
    return PeriodStat(
      avg: values.reduce((a, b) => a + b) / values.length,
      min: lows.reduce((a, b) => a < b ? a : b),
      max: highs.reduce((a, b) => a > b ? a : b),
      days: pts.length,
    );
  }
}

/// Resumen de salud del paciente en los últimos [days] días.
class HealthSummary {
  const HealthSummary({
    required this.days,
    required this.heartRate,
    required this.spo2,
    required this.steps,
    this.adherencePct,
  });

  final int days;
  final PeriodStat heartRate;
  final PeriodStat spo2;
  final PeriodStat steps;
  final double? adherencePct;
}

/// Carga el resumen de un período (30, 60 o 90 días) con las series diarias
/// de vitales y la adherencia a remedios. La temperatura no se incluye.
final healthSummaryProvider =
    FutureProvider.autoDispose.family<HealthSummary?, int>((ref, days) async {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return null;
  final vitals = ref.watch(vitalsRepositoryProvider);
  final meds = ref.watch(medicationsRepositoryProvider);
  final to = DateTime.now();
  final from = to.subtract(Duration(days: days));

  Future<PeriodStat> stat(VitalType type) async {
    try {
      return PeriodStat.of(await vitals.getSeries(patient.patientId, type,
          from: from, to: to, granularity: 'day'));
    } catch (_) {
      return const PeriodStat();
    }
  }

  Future<double?> adherence() async {
    try {
      return (await meds.adherence(patient.patientId, from: from, to: to)).pct;
    } catch (_) {
      return null;
    }
  }

  final results = await Future.wait<Object?>([
    stat(VitalType.heartRate),
    stat(VitalType.spo2),
    stat(VitalType.steps),
    adherence(),
  ]);
  return HealthSummary(
    days: days,
    heartRate: results[0]! as PeriodStat,
    spo2: results[1]! as PeriodStat,
    steps: results[2]! as PeriodStat,
    adherencePct: results[3] as double?,
  );
});

/// Pantalla "Resumen de salud" (feedback del equipo): métricas de los últimos
/// 30, 60 o 90 días para conversar con el médico o la familia.
class HealthSummaryScreen extends ConsumerStatefulWidget {
  const HealthSummaryScreen({super.key});

  static const periods = [30, 60, 90];

  @override
  ConsumerState<HealthSummaryScreen> createState() => _HealthSummaryScreenState();
}

class _HealthSummaryScreenState extends ConsumerState<HealthSummaryScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final patient = ref.watch(selectedPatientProvider);
    final summary = ref.watch(healthSummaryProvider(_days));
    return Scaffold(
      appBar: AppBar(title: const Text('Resumen de salud')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (patient != null)
            Text('${patient.fullName} · últimos $_days días',
                style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            key: const Key('summary-period'),
            segments: [
              for (final d in HealthSummaryScreen.periods)
                ButtonSegment(value: d, label: Text('$d días')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
          const SizedBox(height: 16),
          summary.when(
            loading: () => const Padding(
                padding: EdgeInsets.only(top: 32), child: LoadingView()),
            error: (e, _) => ErrorView(
                message: 'No se pudo cargar el resumen.',
                onRetry: () => ref.invalidate(healthSummaryProvider(_days))),
            data: (s) => s == null
                ? const EmptyView(
                    icon: Icons.person_search_rounded,
                    title: 'Selecciona un paciente',
                    subtitle: 'Elige a quién quieres ver el resumen.')
                : _Metrics(summary: s),
          ),
        ],
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.summary});

  final HealthSummary summary;

  static String _n(double? v) => v == null ? '—' : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final hr = summary.heartRate;
    final o2 = summary.spo2;
    final steps = summary.steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricCard(
          key: const Key('metric-heart'),
          icon: Icons.favorite_rounded,
          title: 'Ritmo cardíaco promedio',
          value: hr.hasData ? '${_n(hr.avg)} lpm' : 'Sin datos',
          detail: hr.hasData
              ? 'Mínimo ${_n(hr.min)} · máximo ${_n(hr.max)} · ${hr.days} días con datos'
              : null,
        ),
        _MetricCard(
          key: const Key('metric-spo2'),
          icon: Icons.air_rounded,
          title: 'Oxígeno (SpO2) promedio',
          value: o2.hasData ? '${_n(o2.avg)} %' : 'Sin datos',
          detail: o2.hasData ? 'Valor más bajo: ${_n(o2.min)} %' : null,
        ),
        _MetricCard(
          key: const Key('metric-steps'),
          icon: Icons.directions_walk_rounded,
          title: 'Pasos por día (promedio)',
          value: steps.hasData ? _n(steps.avg) : 'Sin datos',
          detail: steps.hasData ? 'Mejor día: ${_n(steps.max)} pasos' : null,
        ),
        _MetricCard(
          key: const Key('metric-adherence'),
          icon: Icons.medication_rounded,
          title: 'Remedios tomados a tiempo',
          value: summary.adherencePct == null
              ? 'Sin datos'
              : '${_n(summary.adherencePct)} %',
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(detail!,
                          style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
