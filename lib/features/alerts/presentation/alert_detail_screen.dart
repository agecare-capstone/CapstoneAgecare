import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/domain/models.dart';
import '../../patients/data/patients_repository.dart';
import '../application/alerts_providers.dart';
import '../data/alerts_repository.dart';
import '../domain/models.dart';

/// Número de emergencias (SAMU en Chile) para el botón de la pantalla de caída.
const emergencyNumber = '131';

/// Teléfono de la primera cuidadora del paciente que lo tenga registrado.
/// Si el usuario no puede ver el círculo (o no hay teléfono), null.
final caregiverPhoneProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, patientId) async {
  try {
    final members =
        await ref.watch(patientsRepositoryProvider).listCircleMembers(patientId);
    for (final m in members) {
      final phone = m.phone;
      if (m.role == RoleType.caregiver && phone != null && phone.isNotEmpty) {
        return phone;
      }
    }
  } catch (_) {}
  return null;
});

/// Carga una alerta puntual buscándola en la lista del usuario.
final _alertByIdProvider =
    FutureProvider.autoDispose.family<Alert?, String>((ref, alertId) async {
  final list = await ref.watch(alertsRepositoryProvider).listAlerts();
  for (final a in list) {
    if (a.id == alertId) return a;
  }
  return null;
});

class AlertDetailScreen extends ConsumerStatefulWidget {
  const AlertDetailScreen({super.key, required this.alertId});

  final String alertId;

  @override
  ConsumerState<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends ConsumerState<AlertDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(activeAlertsProvider);
      ref.invalidate(_alertByIdProvider(widget.alertId));
      if (!mounted) return;
      showAppSnackBar(context, okMessage);
      if (context.canPop()) context.pop();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudo completar la acción.', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Abre el marcador del teléfono con [number].
  Future<void> _call(String number) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok && mounted) {
      showAppSnackBar(context, 'No se pudo abrir el marcador ($number).',
          error: true);
    }
  }

  /// Pide la nota de cierre (obligatoria en alertas críticas). null = cancelar.
  Future<String?> _askResolutionNote() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Resolver alerta'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '¿Cómo se atendió?',
              hintText: 'Ej.: Ya está acostada, sin golpes visibles.',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setLocal(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Resolver'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resolve(Alert alert) async {
    String? note;
    if (alert.severity == AlertSeverity.critical) {
      note = await _askResolutionNote();
      if (note == null) return;
    }
    await _run(
        () => ref.read(alertsRepositoryProvider).resolve(alert.id, note: note),
        'Alerta resuelta. Avisamos al resto del grupo.');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_alertByIdProvider(widget.alertId));
    final alert = async.valueOrNull;
    // AGE-505: una caída sin resolver se muestra como pantalla roja de emergencia.
    final emergency =
        alert != null && alert.type == AlertType.fall && !alert.isResolved;

    return Scaffold(
      backgroundColor:
          emergency ? AppColors.critical.withOpacity(.06) : null,
      appBar: AppBar(
        title: Text(emergency ? 'Caída detectada' : 'Detalle de alerta'),
        backgroundColor: emergency ? AppColors.critical : null,
        foregroundColor: emergency ? Colors.white : null,
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: e is ApiException ? e.message : 'No pudimos cargar la alerta.',
          onRetry: () => ref.invalidate(_alertByIdProvider(widget.alertId)),
        ),
        data: (alert) {
          if (alert == null) {
            return const EmptyView(
              icon: Icons.search_off_rounded,
              title: 'Alerta no encontrada',
              subtitle: 'Es posible que ya haya sido resuelta o eliminada.',
            );
          }
          final caregiverPhone = alert.type == AlertType.fall
              ? ref.watch(caregiverPhoneProvider(alert.patientId)).valueOrNull
              : null;
          return _AlertDetailBody(
            alert: alert,
            busy: _busy,
            onCallCaregiver:
                caregiverPhone == null ? null : () => _call(caregiverPhone),
            onCallEmergency: () => _call(emergencyNumber),
            onAcknowledge: () => _run(
                () => ref.read(alertsRepositoryProvider).acknowledge(alert.id),
                'Alerta reconocida'),
            onResolve: () => _resolve(alert),
          );
        },
      ),
    );
  }
}

class _AlertDetailBody extends StatelessWidget {
  const _AlertDetailBody({
    required this.alert,
    required this.busy,
    required this.onCallCaregiver,
    required this.onCallEmergency,
    required this.onAcknowledge,
    required this.onResolve,
  });

  final Alert alert;
  final bool busy;

  /// null si no hay cuidadora con teléfono registrado.
  final VoidCallback? onCallCaregiver;
  final VoidCallback onCallEmergency;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final color = alert.severity.color;
    final isFall = alert.type == AlertType.fall;
    final resolved = alert.isResolved;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Encabezado con severidad
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(.4)),
          ),
          child: Row(
            children: [
              Icon(alert.type.icon, color: color, size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: color)),
                    const SizedBox(height: 2),
                    Text('${alert.severity.label} · ${alertTimeAgo(alert.createdAt)}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Flujo crítico para caídas
        if (isFall && !resolved) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.priority_high_rounded, color: AppColors.critical),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Situación crítica',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.critical)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Llama a la cuidadora para confirmar el estado del adulto mayor. '
                  'Si no responde o hay lesiones, llama a emergencias.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.critical,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: onCallCaregiver,
                  icon: const Icon(Icons.call_rounded),
                  label: Text(onCallCaregiver == null
                      ? 'Cuidadora sin teléfono registrado'
                      : 'Llamar a Cuidadora'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.critical,
                    side: const BorderSide(color: AppColors.critical),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: onCallEmergency,
                  icon: const Icon(Icons.local_hospital_rounded),
                  label: const Text('Llamar a Emergencias ($emergencyNumber)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Mensaje / contexto
        _SectionTitle('¿Qué ocurrió?'),
        const SizedBox(height: 6),
        AppCard(
          child: Text(alert.message,
              style: const TextStyle(fontSize: 15, height: 1.4)),
        ),
        const SizedBox(height: 16),

        // Detalles
        _SectionTitle('Detalles'),
        const SizedBox(height: 6),
        AppCard(
          child: Column(
            children: [
              if (alert.patientName.isNotEmpty)
                _DetailRow('Paciente', alert.patientName),
              _DetailRow('Tipo', alert.type.label),
              _DetailRow('Estado', alert.status.label),
              _DetailRow(
                'Detectada',
                DateFormat('dd/MM HH:mm').format(alert.createdAt.toLocal()),
              ),
              if (alert.acknowledgedBy != null)
                _DetailRow('Reconocida por', alert.acknowledgedBy!),
              if (alert.resolvedAt != null)
                _DetailRow(
                    'Resuelta',
                    DateFormat('dd/MM HH:mm').format(alert.resolvedAt!.toLocal())),
              ...?_metaRows(alert.meta),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Acciones
        if (!resolved) ...[
          if (alert.status == AlertStatus.active)
            OutlinedButton.icon(
              onPressed: busy ? null : onAcknowledge,
              icon: const Icon(Icons.done_rounded),
              label: const Text('Reconocer'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
            ),
          if (alert.status == AlertStatus.active) const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : onResolve,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.task_alt_rounded),
            label: const Text('Resolver alerta'),
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.statusOk.withOpacity(.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.statusOk),
                SizedBox(width: 10),
                Expanded(
                    child: Text('Esta alerta ya fue resuelta.',
                        style: TextStyle(
                            color: AppColors.statusOk,
                            fontWeight: FontWeight.w600))),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget>? _metaRows(Map<String, dynamic>? meta) {
    if (meta == null || meta.isEmpty) return null;
    return meta.entries
        .map((e) => _DetailRow(_prettyKey(e.key), '${e.value}'))
        .toList();
  }

  String _prettyKey(String key) {
    const map = {
      'location': 'Ubicación',
      'confidence': 'Confianza',
      'vital': 'Signo vital',
      'value': 'Valor',
      'unit': 'Unidad',
      'medication': 'Medicamento',
      'scheduled': 'Programado',
      'last_sync_hours': 'Última sync (h)',
      'lat': 'Latitud',
      'lng': 'Longitud',
    };
    return map[key] ?? key;
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
