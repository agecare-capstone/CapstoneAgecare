import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/auth_controller.dart';
import '../application/caregiver_providers.dart';
import '../domain/models.dart';
import 'report_pdf.dart';

/// Reportes de actividad de la cuidadora (DAC05-93): rango de fechas, serie
/// diaria y exportación a PDF. El plan gratuito ve los últimos 30 días.
class CaregiverReportsScreen extends ConsumerStatefulWidget {
  const CaregiverReportsScreen({super.key, this.shareFile, this.buildPdf});

  static const ranges = [7, 30, 90];

  /// Para pruebas: reemplaza el diálogo de compartir del sistema.
  final Future<void> Function(XFile file, String fileName)? shareFile;

  /// Para pruebas: reemplaza la generación del PDF (que lee fuente y logo del disco).
  final Future<Uint8List> Function(CaregiverReport report, String caregiverName)? buildPdf;

  @override
  ConsumerState<CaregiverReportsScreen> createState() => _CaregiverReportsScreenState();
}

class _CaregiverReportsScreenState extends ConsumerState<CaregiverReportsScreen> {
  int _days = 7;
  bool _exporting = false;

  bool get _isFree => ref.read(caregiverPlanProvider).valueOrNull?.tier.isFree ?? true;

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(caregiverReportProvider(_days));
    ref.watch(caregiverPlanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis reportes'),
        actions: [
          IconButton(
            key: const Key('export-pdf'),
            tooltip: 'Exportar PDF',
            icon: _exporting
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_rounded),
            onPressed: _exporting ? null : () => _export(reportAsync.valueOrNull),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(caregiverReportProvider(_days));
          ref.invalidate(caregiverPlanProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            SegmentedButton<int>(
              key: const Key('report-range'),
              segments: [
                for (final d in CaregiverReportsScreen.ranges)
                  ButtonSegment(value: d, label: Text('$d días')),
              ],
              selected: {_days},
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
            const SizedBox(height: 16),
            reportAsync.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 40), child: LoadingView()),
              error: (e, _) => e is PremiumRequiredException
                  ? const _PremiumUpsell(
                      title: 'Más de 30 días es Premium',
                      message: 'Con el plan gratuito ves los últimos 30 días. '
                          'Pasa a Premium para ver 90 días y exportar tus reportes en PDF.',
                    )
                  : ErrorView(
                      message: 'No se pudo cargar el reporte.',
                      onRetry: () => ref.invalidate(caregiverReportProvider(_days)),
                    ),
              data: (report) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(report.period, style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  _MetricsGrid(report: report),
                  const SizedBox(height: 20),
                  Text('Tareas completadas por día',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  AppCard(child: SizedBox(height: 200, child: _DailyChart(days: report.daily))),
                  if (_isFree) ...[
                    const SizedBox(height: 20),
                    const _PremiumUpsell(
                      title: 'Desbloquea reportes avanzados',
                      message:
                          'Con Premium ves hasta 90 días y exportas tus reportes en PDF con el logo de AgeCare.',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(CaregiverReport? report) async {
    if (report == null) return;
    if (_isFree) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Exportar PDF es Premium'),
          content: const Text('Pasa a Premium para descargar y compartir tus reportes en PDF.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ahora no')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/premium');
              },
              child: const Text('Ver planes'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final name = ref.read(currentUserProvider)?.fullName ?? 'Cuidadora';
      final build = widget.buildPdf ?? (r, n) => buildReportPdf(r, caregiverName: n);
      final bytes = await build(report, name);
      final fileName = 'reporte-agecare-${report.to.toIso8601String().substring(0, 10)}.pdf';
      final file = XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf');
      final share = widget.shareFile ??
          (f, n) =>
              Share.shareXFiles([f], text: 'Reporte de actividad AgeCare', fileNameOverrides: [n]);
      await share(file, fileName);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'No se pudo generar el PDF.', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.report});

  final CaregiverReport report;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricData(Icons.check_circle_rounded, '${report.tasksDone}', 'Tareas completadas',
          AppColors.statusOk),
      _MetricData(Icons.medication_rounded, '${report.dosesGiven}', 'Dosis administradas',
          AppColors.primary),
      _MetricData(Icons.verified_rounded, '${report.adherencePct.round()}%', 'Adherencia',
          AppColors.secondary),
      _MetricData(Icons.edit_note_rounded, '${report.observations}', 'Observaciones',
          AppColors.statusWarning),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [for (final m in metrics) _MetricCard(data: m)],
    );
  }
}

class _MetricData {
  const _MetricData(this.icon, this.value, this.label, this.color);
  final IconData icon;
  final String value;
  final String label;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(data.icon, color: data.color, size: 26),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child:
                Text(data.value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 2),
          Text(data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.days});

  final List<ReportDay> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const Center(
        child:
            Text('Sin datos para este periodo', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    final maxY = days.map((d) => d.tasksDone).reduce((a, b) => a > b ? a : b).toDouble();
    // Con muchos días se rotulan solo algunos, para que no se encimen.
    final every = (days.length / 7).ceil();
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY + 1,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => const FlLine(color: AppColors.divider, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= days.length || i % every != 0) return const SizedBox.shrink();
                final d = days[i].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${d.day}/${d.month}',
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: days[i].tasksDone.toDouble(),
                width: days.length > 14 ? 5 : 14,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                color: AppColors.primary,
              ),
            ]),
        ],
      ),
    );
  }
}

class _PremiumUpsell extends StatelessWidget {
  const _PremiumUpsell({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('premium-upsell'),
      onTap: () => context.push('/premium'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.statusWarning.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: AppColors.statusWarning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child:
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => context.push('/premium'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusWarning),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Ver planes Premium'),
          ),
        ],
      ),
    );
  }
}
