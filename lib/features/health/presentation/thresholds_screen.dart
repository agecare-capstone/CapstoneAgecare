import 'package:flutter/material.dart' hide Threshold;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/domain/models.dart';
import '../../patients/application/patients_providers.dart';
import '../data/vitals_repository.dart';
import '../domain/models.dart';
import 'health_screen.dart' show latestVitalsProvider;

/// Vitales con umbral configurable (los mismos que crea el backend por defecto).
const editableVitals = [VitalType.heartRate, VitalType.spo2, VitalType.temperature];

/// Umbrales de alerta del paciente seleccionado.
final thresholdsProvider = FutureProvider.autoDispose<List<Threshold>>((ref) {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return const [];
  return ref.watch(vitalsRepositoryProvider).getThresholds(patient.patientId);
});

/// Configuración de umbrales de alerta por vital (AGE-507).
///
/// El familiar o el médico ajustan el mínimo y el máximo de cada vital; las
/// alertas del backend se disparan con estos valores. La cuidadora solo los ve.
class ThresholdsScreen extends ConsumerWidget {
  const ThresholdsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = ref.watch(selectedPatientProvider);
    final async = ref.watch(thresholdsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Umbrales de alerta')),
      body: patient == null
          ? const EmptyView(
              icon: Icons.person_off_rounded,
              title: 'Sin paciente seleccionado',
              subtitle: 'Selecciona un paciente para ver sus umbrales.',
            )
          : async.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(thresholdsProvider),
              ),
              data: (thresholds) {
                final canEdit = patient.role == RoleType.family ||
                    patient.role == RoleType.doctor;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(
                      canEdit
                          ? 'Se genera una alerta cuando una lectura de '
                              '${patient.fullName} queda fuera de estos rangos.'
                          : 'Solo el familiar o el médico pueden cambiar los '
                              'umbrales de ${patient.fullName}.',
                      style: const TextStyle(
                          color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    for (final type in editableVitals) ...[
                      ThresholdCard(
                        key: ValueKey(type),
                        patientId: patient.patientId,
                        initial: thresholds.firstWhere(
                          (t) => t.type == type,
                          orElse: () => Threshold(type: type),
                        ),
                        enabled: canEdit,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

/// Tarjeta de un vital: campos de mínimo y máximo y botón Guardar.
class ThresholdCard extends ConsumerStatefulWidget {
  const ThresholdCard({
    super.key,
    required this.patientId,
    required this.initial,
    required this.enabled,
  });

  final String patientId;
  final Threshold initial;
  final bool enabled;

  @override
  ConsumerState<ThresholdCard> createState() => _ThresholdCardState();
}

class _ThresholdCardState extends ConsumerState<ThresholdCard> {
  late final _min = TextEditingController(text: _format(widget.initial.minValue));
  late final _max = TextEditingController(text: _format(widget.initial.maxValue));
  late Threshold _saved = widget.initial;
  String? _error;
  bool _saving = false;

  VitalType get _type => widget.initial.type;

  static String _format(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  static double? _parse(String text) {
    final t = text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  bool get _dirty =>
      _parse(_min.text) != _saved.minValue ||
      _parse(_max.text) != _saved.maxValue;

  /// Mismas reglas que el backend (EMPTY_THRESHOLD / INVALID_THRESHOLD_RANGE).
  String? _validate(double? min, double? max) {
    if ((_min.text.trim().isNotEmpty && min == null) ||
        (_max.text.trim().isNotEmpty && max == null)) {
      return 'Ingresa solo números.';
    }
    if (min == null && max == null) {
      return 'Indica al menos un valor mínimo o máximo.';
    }
    if (min != null && max != null && min > max) {
      return 'El mínimo no puede ser mayor que el máximo.';
    }
    return null;
  }

  Future<void> _save() async {
    final min = _parse(_min.text);
    final max = _parse(_max.text);
    final error = _validate(min, max);
    setState(() => _error = error);
    if (error != null) return;

    setState(() => _saving = true);
    try {
      final saved = await ref.read(vitalsRepositoryProvider).updateThreshold(
          widget.patientId, Threshold(type: _type, minValue: min, maxValue: max));
      // El estado de las tarjetas de Salud depende de los umbrales.
      ref.invalidate(latestVitalsProvider);
      if (!mounted) return;
      setState(() => _saved = saved);
      showAppSnackBar(context, 'Umbral de ${_type.label} guardado.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo guardar. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_type.icon, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_type.label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Text(_type.unit,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _field(_min, 'Mínimo')),
              const SizedBox(width: 12),
              Expanded(child: _field(_max, 'Máximo')),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: AppColors.critical, fontSize: 13)),
          ],
          if (widget.enabled) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving || !_dirty ? null : _save,
                child: Text(_saving ? 'Guardando...' : 'Guardar'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      enabled: widget.enabled && !_saving,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Sin límite',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) => setState(() => _error = null),
    );
  }
}
