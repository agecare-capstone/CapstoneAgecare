import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../patients/application/patients_providers.dart';
import '../data/vitals_repository.dart';
import '../domain/models.dart';

final latestVitalsProvider = FutureProvider<List<LatestVital>>((ref) async {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return [];
  return ref.watch(vitalsRepositoryProvider).getLatest(patient.patientId);
});

/// Pantalla Salud: tarjetas de vitals con último valor y acceso al detalle
/// con tendencias (ticket AGE-304).
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = ref.watch(selectedPatientProvider);
    final latest = ref.watch(latestVitalsProvider);
    final detail = ref.watch(selectedPatientDetailProvider);

    if (patient == null) {
      return const EmptyView(
          icon: Icons.monitor_heart_outlined,
          title: 'Sin paciente seleccionado',
          subtitle: 'Crea o selecciona un paciente para ver su salud.');
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(latestVitalsProvider);
        ref.invalidate(selectedPatientDetailProvider);
      },
      child: latest.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(latestVitalsProvider)),
        data: (vitals) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Estado del wearable (ticket AGE-306, criterio de visibilidad de sync)
            detail.maybeWhen(
              data: (p) => p?.wearable != null
                  ? _WearableStatusCard(
                      lastSync: p!.wearable!.lastSyncAt,
                      battery: p.wearable!.batteryPct,
                      isStale: p.wearable!.isStale,
                    )
                  : const _WearableLinkCard(),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            if (vitals.isEmpty)
              const EmptyView(
                  icon: Icons.watch_outlined,
                  title: 'Aún no hay lecturas',
                  subtitle:
                      'Cuando el wearable sincronice, verás aquí los vitals con sus tendencias.')
            else ...[
              _VitalGroup(
                title: 'Vitales',
                vitals: vitals
                    .where((v) => v.type.isCoreVital && !v.type.isHidden)
                    .toList(),
              ),
              _VitalGroup(
                title: 'Actividad',
                vitals: vitals
                    .where((v) => !v.type.isCoreVital && !v.type.isHidden)
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Grupo de tarjetas de vitals con encabezado (AGE-304 / DAC05-60).
/// No se dibuja si no hay vitals de ese grupo para el paciente.
class _VitalGroup extends StatelessWidget {
  const _VitalGroup({required this.title, required this.vitals});

  final String title;
  final List<LatestVital> vitals;

  @override
  Widget build(BuildContext context) {
    if (vitals.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...vitals.map((v) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _VitalCard(vital: v),
              )),
        ],
      ),
    );
  }
}

class _VitalCard extends ConsumerWidget {
  const _VitalCard({required this.vital});

  final LatestVital vital;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = vital.inRange ? AppColors.primary : AppColors.statusAttention;
    return AppCard(
      onTap: () => context.push('/health/vital/${vital.type.apiValue}'),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(vital.type.icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vital.type.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(vital.displayValue,
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w800, color: color)),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(vital.type.unit,
                          style: const TextStyle(color: AppColors.textSecondary)),
                    ),
                  ],
                ),
                Text(
                  'Última lectura ${DateFormat('HH:mm').format(vital.measuredAt.toLocal())}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (!vital.inRange)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.error_rounded, color: AppColors.statusAttention),
            ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _WearableStatusCard extends StatelessWidget {
  const _WearableStatusCard({this.lastSync, this.battery, required this.isStale});

  final DateTime? lastSync;
  final int? battery;
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    final color = isStale ? AppColors.statusWarning : AppColors.statusOk;
    final syncText = lastSync == null
        ? 'sin datos'
        : 'hace ${_ago(DateTime.now().difference(lastSync!.toLocal()))}';
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.watch_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isStale
                  ? 'Wearable sin datos recientes (última sync $syncText)'
                  : 'Wearable sincronizado $syncText',
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          if (battery != null) ...[
            Icon(
                battery! > 20
                    ? Icons.battery_std_rounded
                    : Icons.battery_alert_rounded,
                size: 18,
                color: battery! > 20 ? AppColors.textSecondary : AppColors.critical),
            Text('$battery%',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }

  String _ago(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    return '${d.inDays} días';
  }
}

class _WearableLinkCard extends StatelessWidget {
  const _WearableLinkCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.watch_off_outlined, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Sin wearable vinculado',
                  style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () => showAppSnackBar(
                context, 'La vinculación se conecta con Spike en Configuración'),
            child: const Text('Vincular'),
          ),
        ],
      ),
    );
  }
}
