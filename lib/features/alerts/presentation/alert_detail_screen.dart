import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/domain/models.dart';
import '../../patients/application/patients_providers.dart';
import '../../patients/data/patients_repository.dart';
import '../../patients/domain/models.dart';
import '../application/alarm_player.dart';
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

/// Paciente de la alerta, para mostrar su domicilio en la pantalla de caída.
/// Si no se puede cargar, la pantalla sigue funcionando sin él.
final alertPatientProvider =
    FutureProvider.autoDispose.family<Patient?, String>((ref, patientId) async {
  try {
    return await ref.watch(patientsRepositoryProvider).getPatient(patientId);
  } catch (_) {
    return null;
  }
});

/// Última ubicación conocida de la alerta (lat/lng del reloj o del SOS).
({double lat, double lng})? alertLocation(Alert alert) {
  final lat = alert.meta?['lat'];
  final lng = alert.meta?['lng'];
  if (lat is num && lng is num) return (lat: lat.toDouble(), lng: lng.toDouble());
  return null;
}

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

  /// La alarma suena una sola vez por apertura de la pantalla (DAC05-84).
  bool _alarmStarted = false;
  bool _alarmOn = false;
  AlarmPlayer? _alarm;

  void _startAlarm() {
    if (_alarmStarted || !mounted) return;
    _alarmStarted = true;
    _alarm = ref.read(alarmPlayerProvider);
    setState(() => _alarmOn = true);
    _alarm!.start();
  }

  Future<void> _silence() async {
    if (!_alarmOn) return;
    setState(() => _alarmOn = false);
    await _alarm?.stop();
  }

  @override
  void dispose() {
    if (_alarmOn) _alarm?.stop();
    super.dispose();
  }

  Future<void> _openMap(({double lat, double lng}) at) async {
    final ok = await launchUrl(
      Uri.https('www.google.com', '/maps/search/',
          {'api': '1', 'query': '${at.lat},${at.lng}'}),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      showAppSnackBar(context, 'No se pudo abrir el mapa.', error: true);
    }
  }

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    _silence();
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
    _silence();
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok && mounted) {
      showAppSnackBar(context, 'No se pudo abrir el marcador ($number).',
          error: true);
    }
  }

  /// Pide la nota de cierre (obligatoria en alertas críticas y al descartar
  /// una falsa alarma). null = cancelar.
  Future<String?> _askResolutionNote({
    String title = 'Resolver alerta',
    String label = '¿Cómo se atendió?',
    String hint = 'Ej.: Ya está acostada, sin golpes visibles.',
    String action = 'Resolver',
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 300,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
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
              child: Text(action),
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

  /// "Confirmar falsa alarma" (DAC05-85): cierra la alerta con una
  /// justificación obligatoria que queda registrada en el backend.
  Future<void> _confirmFalseAlarm(Alert alert) async {
    final note = await _askResolutionNote(
      title: 'Confirmar falsa alarma',
      label: '¿Por qué es una falsa alarma?',
      hint: 'Ej.: Se le cayó el reloj; ella está bien.',
      action: 'Confirmar',
    );
    if (note == null) return;
    await _run(
        () => ref
            .read(alertsRepositoryProvider)
            .resolve(alert.id, note: note, falseAlarm: true),
        'Marcada como falsa alarma. Avisamos al resto del grupo.');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_alertByIdProvider(widget.alertId));
    final alert = async.valueOrNull;
    // AGE-505: una caída sin resolver se muestra como pantalla roja de emergencia.
    final emergency =
        alert != null && alert.type == AlertType.fall && !alert.isResolved;
    if (emergency && !_alarmStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAlarm());
    }

    return Scaffold(
      backgroundColor:
          emergency ? AppColors.critical.withValues(alpha: .06) : null,
      appBar: AppBar(
        // El tema fija el color del título: en la caída va blanco sobre rojo.
        title: Text(emergency ? 'Caída detectada' : 'Detalle de alerta',
            style: emergency ? const TextStyle(color: Colors.white) : null),
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
          // La cuidadora no se llama a sí misma: ella solo ve el 131.
          final myPatients = ref.watch(myPatientsProvider).valueOrNull ?? [];
          final viewerIsCaregiver = myPatients.any((p) =>
              p.patientId == alert.patientId && p.role == RoleType.caregiver);
          final caregiverPhone =
              alert.type == AlertType.fall && !viewerIsCaregiver
                  ? ref.watch(caregiverPhoneProvider(alert.patientId)).valueOrNull
                  : null;
          final location = alertLocation(alert);
          return _AlertDetailBody(
            alert: alert,
            busy: _busy,
            viewerIsCaregiver: viewerIsCaregiver,
            patientAddress: alert.type == AlertType.fall
                ? ref.watch(alertPatientProvider(alert.patientId)).valueOrNull?.address
                : null,
            onSilence: _alarmOn ? _silence : null,
            onOpenMap: location == null ? null : () => _openMap(location),
            onCallCaregiver:
                caregiverPhone == null ? null : () => _call(caregiverPhone),
            onCallEmergency: () => _call(emergencyNumber),
            onAcknowledge: () => _run(
                () => ref.read(alertsRepositoryProvider).acknowledge(alert.id),
                'Marcada como vista'),
            onResolve: () => _resolve(alert),
            onFalseAlarm: alert.severity == AlertSeverity.critical
                ? () => _confirmFalseAlarm(alert)
                : null,
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
    this.viewerIsCaregiver = false,
    required this.onCallCaregiver,
    required this.onCallEmergency,
    required this.onAcknowledge,
    required this.onResolve,
    this.onFalseAlarm,
    this.patientAddress,
    this.onSilence,
    this.onOpenMap,
  });

  final Alert alert;
  final bool busy;

  /// Domicilio del adulto mayor (solo en caídas).
  final String? patientAddress;

  /// Silenciar la alarma; null si no está sonando.
  final VoidCallback? onSilence;

  /// Abrir la última ubicación en el mapa; null si no hay ubicación.
  final VoidCallback? onOpenMap;

  /// Quien mira la alerta es la cuidadora del paciente.
  final bool viewerIsCaregiver;

  /// null si no hay cuidadora con teléfono registrado.
  final VoidCallback? onCallCaregiver;
  final VoidCallback onCallEmergency;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;

  /// Solo en alertas críticas (caída, SOS).
  final VoidCallback? onFalseAlarm;

  @override
  Widget build(BuildContext context) {
    final isFall = alert.type == AlertType.fall;
    final resolved = alert.isResolved;
    // AGE-505 / DAC05-84: caída sin resolver = fondo rojo de alta visibilidad.
    final emergency = isFall && !resolved;
    final color = emergency ? Colors.white : alert.severity.color;
    final location = alertLocation(alert);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Encabezado con severidad
        Container(
          key: const ValueKey('alert-header'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: emergency
                ? AppColors.critical
                : alert.severity.color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: emergency
                    ? AppColors.critical
                    : alert.severity.color.withValues(alpha: .4)),
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
                        style: TextStyle(
                            color: emergency
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onSilence != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.critical,
              side: const BorderSide(color: AppColors.critical),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: onSilence,
            icon: const Icon(Icons.volume_off_rounded),
            label: const Text('Silenciar alarma'),
          ),
        ],
        const SizedBox(height: 16),

        // Datos del adulto mayor para ir a ayudarlo (DAC05-84).
        if (emergency) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Adulto mayor',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _InfoLine(
                  icon: Icons.person_rounded,
                  text: alert.patientName.isEmpty
                      ? 'Paciente'
                      : alert.patientName,
                ),
                _InfoLine(
                  icon: Icons.home_rounded,
                  text: patientAddress ?? 'Domicilio no registrado',
                  muted: patientAddress == null,
                ),
                _InfoLine(
                  icon: Icons.location_on_rounded,
                  text: location == null
                      ? 'Sin ubicación registrada'
                      : 'Última ubicación: ${location.lat.toStringAsFixed(5)}, '
                          '${location.lng.toStringAsFixed(5)}',
                  muted: location == null,
                ),
                if (onOpenMap != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onOpenMap,
                      icon: const Icon(Icons.map_rounded),
                      label: const Text('Ver en el mapa'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Flujo crítico para caídas
        if (isFall && !resolved) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
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
                Text(
                  viewerIsCaregiver
                      ? 'Revisa al adulto mayor ahora. '
                          'Si no responde o hay lesiones, llama a emergencias.'
                      : 'Llama a la cuidadora para confirmar el estado del adulto mayor. '
                          'Si no responde o hay lesiones, llama a emergencias.',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 14),
                if (!viewerIsCaregiver)
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
                if (!viewerIsCaregiver) const SizedBox(height: 10),
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
        const _SectionTitle('¿Qué ocurrió?'),
        const SizedBox(height: 6),
        AppCard(
          child: Text(alert.message,
              style: const TextStyle(fontSize: 15, height: 1.4)),
        ),
        const SizedBox(height: 16),

        // Detalles
        const _SectionTitle('Detalles'),
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
              if (alert.resolutionNote != null)
                _DetailRow('Nota', alert.resolutionNote!),
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
              label: const Text(alertSeenLabel),
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
            label: Text(alert.type.resolveLabel),
          ),
          if (onFalseAlarm != null) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: busy ? null : onFalseAlarm,
              icon: const Icon(Icons.do_not_disturb_on_outlined),
              label: const Text('Confirmar falsa alarma'),
            ),
          ],
        ] else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.statusOk.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.statusOk),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        alert.falseAlarm
                            ? 'Descartada como falsa alarma.'
                            : 'Esta alerta ya fue resuelta.',
                        style: const TextStyle(
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
    const hidden = {
      'lat', 'lng', 'telemetry', 'source', 'event_type', 'triggered_by',
      'measured_at',
    };
    return meta.entries
        .where((e) => !hidden.contains(e.key) && e.value != null)
        .map((e) => _DetailRow(_prettyKey(e.key), _prettyValue(e.key, e.value)))
        .toList();
  }

  String _prettyValue(String key, Object? value) {
    if (key == 'confidence_level' && value is num) {
      return '${(value * 100).round()}%';
    }
    return '$value';
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
      'confidence_level': 'Confianza',
      'vital_type': 'Signo vital',
      'min_value': 'Mínimo',
      'max_value': 'Máximo',
      'note': 'Nota',
    };
    return map[key] ?? key;
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.critical),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 15,
                      color: muted
                          ? AppColors.textSecondary
                          : AppColors.textPrimary)),
            ),
          ],
        ),
      );
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
