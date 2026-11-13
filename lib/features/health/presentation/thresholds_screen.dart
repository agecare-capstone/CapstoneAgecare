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
const editableVitals = [
  VitalType.heartRate,
  VitalType.spo2,
  VitalType.bloodPressure,
];

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
                final canEdit = patient.role == RoleType.doctor ||
                    (patient.role == RoleType.family && patient.isOwner);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(
                      canEdit
                          ? 'Se genera una alerta cuando una lectura de '
                              '${patient.fullName} queda fuera de estos rangos.'
                          : 'Solo el familiar administrador o el médico pueden '
                              'cambiar los umbrales de ${patient.fullName}.',
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

/// Rango de un valor del umbral: límites biológicamente posibles (fuera de
/// ellos es un error de tipeo), paso del slider y valores recomendados.
/// Los mismos límites que valida el backend (THRESHOLD_OUT_OF_BIOLOGICAL_RANGE).
class ThresholdSpec {
  const ThresholdSpec({
    required this.lowest,
    required this.highest,
    this.step = 1,
    this.recommendedMin,
    this.recommendedMax,
    this.label,
  });

  final double lowest;
  final double highest;
  final double step;
  final double? recommendedMin;
  final double? recommendedMax;

  /// Nombre de la fila cuando el vital tiene dos valores (sistólica/diastólica).
  final String? label;

  int get divisions => ((highest - lowest) / step).round();
}

/// Especificación por vital; la presión arterial tiene dos filas.
/// Los recomendados son los que el backend crea al registrar un paciente.
const thresholdSpecs = <VitalType, List<ThresholdSpec>>{
  VitalType.heartRate: [
    ThresholdSpec(
        lowest: 30, highest: 250, recommendedMin: 50, recommendedMax: 110),
  ],
  VitalType.spo2: [
    ThresholdSpec(lowest: 50, highest: 100, recommendedMin: 92),
  ],
  VitalType.temperature: [
    ThresholdSpec(
        lowest: 30,
        highest: 45,
        step: 0.1,
        recommendedMin: 35.5,
        recommendedMax: 37.8),
  ],
  VitalType.bloodPressure: [
    ThresholdSpec(
        lowest: 50, highest: 260, recommendedMax: 140, label: 'Sistólica'),
    ThresholdSpec(
        lowest: 30, highest: 150, recommendedMax: 90, label: 'Diastólica'),
  ],
};

/// Campos de mínimo y máximo de una fila del umbral.
class _RangeRow {
  _RangeRow(this.spec, double? min, double? max)
      : min = TextEditingController(text: _format(min)),
        max = TextEditingController(text: _format(max));

  final ThresholdSpec spec;
  final TextEditingController min;
  final TextEditingController max;

  double? get minValue => _parse(min.text);
  double? get maxValue => _parse(max.text);

  bool get hasBadNumber =>
      (min.text.trim().isNotEmpty && minValue == null) ||
      (max.text.trim().isNotEmpty && maxValue == null);

  void set(double? lo, double? hi) {
    min.text = _format(lo);
    max.text = _format(hi);
  }

  void dispose() {
    min.dispose();
    max.dispose();
  }

  static String _format(double? v) {
    if (v == null) return '';
    final rounded = double.parse(v.toStringAsFixed(1));
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toString();
  }

  static double? _parse(String text) {
    final t = text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }
}

/// Tarjeta de un vital: slider y campos de mínimo y máximo, botón Guardar y
/// "Restablecer a valores recomendados" (DAC05-196).
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
  late final List<_RangeRow> _rows = [
    for (final (i, spec) in thresholdSpecs[_type]!.indexed)
      i == 0
          ? _RangeRow(spec, widget.initial.minValue, widget.initial.maxValue)
          : _RangeRow(
              spec, widget.initial.minSecondary, widget.initial.maxSecondary),
  ];
  late Threshold _saved = widget.initial;
  String? _error;
  bool _saving = false;

  VitalType get _type => widget.initial.type;
  bool get _hasSecondary => _rows.length > 1;

  Threshold get _current => Threshold(
        type: _type,
        minValue: _rows[0].minValue,
        maxValue: _rows[0].maxValue,
        minSecondary: _hasSecondary ? _rows[1].minValue : null,
        maxSecondary: _hasSecondary ? _rows[1].maxValue : null,
      );

  bool get _dirty {
    final c = _current;
    return c.minValue != _saved.minValue ||
        c.maxValue != _saved.maxValue ||
        c.minSecondary != _saved.minSecondary ||
        c.maxSecondary != _saved.maxSecondary;
  }

  /// Mismas reglas que el backend (EMPTY_THRESHOLD, INVALID_THRESHOLD_RANGE y
  /// THRESHOLD_OUT_OF_BIOLOGICAL_RANGE).
  String? _validate() {
    if (_rows.any((r) => r.hasBadNumber)) return 'Ingresa solo números.';
    if (_rows[0].minValue == null && _rows[0].maxValue == null) {
      return _hasSecondary
          ? 'Indica al menos un valor de la sistólica.'
          : 'Indica al menos un valor mínimo o máximo.';
    }
    for (final r in _rows) {
      final lo = r.minValue, hi = r.maxValue;
      final who =
          r.spec.label == null ? '' : ' (${r.spec.label!.toLowerCase()})';
      if (lo != null && hi != null && lo >= hi) {
        return 'El mínimo debe ser menor que el máximo$who.';
      }
      for (final v in [lo, hi]) {
        if (v != null && (v < r.spec.lowest || v > r.spec.highest)) {
          return 'Usa valores entre ${_RangeRow._format(r.spec.lowest)} y '
              '${_RangeRow._format(r.spec.highest)} ${_type.unit}$who.';
        }
      }
    }
    return null;
  }

  void _reset() {
    setState(() {
      for (final r in _rows) {
        r.set(r.spec.recommendedMin, r.spec.recommendedMax);
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final error = _validate();
    setState(() => _error = error);
    if (error != null) return;

    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(vitalsRepositoryProvider)
          .updateThreshold(widget.patientId, _current);
      // El estado de las tarjetas de Salud depende de los umbrales.
      ref.invalidate(latestVitalsProvider);
      if (!mounted) return;
      setState(() => _saved = saved);
      showAppSnackBar(context, 'Umbral de ${_type.label} guardado.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo guardar. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.enabled && !_saving;
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
          for (final r in _rows) ...[
            const SizedBox(height: 14),
            if (r.spec.label != null) ...[
              Text(r.spec.label!,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(child: _field(r.min, 'Mínimo', editable)),
                const SizedBox(width: 12),
                Expanded(child: _field(r.max, 'Máximo', editable)),
              ],
            ),
            _slider(r, editable),
          ],
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!,
                style:
                    const TextStyle(color: AppColors.critical, fontSize: 13)),
          ],
          if (widget.enabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: TextButton.icon(
                    onPressed: _saving ? null : _reset,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Restablecer a valores recomendados'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving || !_dirty ? null : _save,
                  child: Text(_saving ? 'Guardando...' : 'Guardar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Slider de doble manija sobre el rango biológico. Un extremo vacío ("sin
  /// límite") se dibuja en el borde y sigue vacío mientras no se mueva.
  Widget _slider(_RangeRow r, bool editable) {
    final s = r.spec;
    double clamp(double v) => v.clamp(s.lowest, s.highest).toDouble();
    final end = clamp(r.maxValue ?? s.highest);
    final start = clamp(r.minValue ?? s.lowest).clamp(s.lowest, end).toDouble();
    double snap(double v) =>
        double.parse((s.lowest + ((v - s.lowest) / s.step).round() * s.step)
            .toStringAsFixed(1));
    return RangeSlider(
      values: RangeValues(start, end),
      min: s.lowest,
      max: s.highest,
      divisions: s.divisions,
      labels: RangeLabels(_RangeRow._format(start), _RangeRow._format(end)),
      onChanged: editable
          ? (v) => setState(() {
                if (v.start != start) {
                  r.min.text = _RangeRow._format(snap(v.start));
                }
                if (v.end != end) {
                  r.max.text = _RangeRow._format(snap(v.end));
                }
                _error = null;
              })
          : null,
    );
  }

  Widget _field(TextEditingController controller, String label, bool editable) {
    return TextField(
      controller: controller,
      enabled: editable,
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
