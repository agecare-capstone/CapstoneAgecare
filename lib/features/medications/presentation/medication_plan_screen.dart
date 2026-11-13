import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/notifications/push_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/medical_disclaimer.dart';
import '../application/medications_providers.dart';
import '../data/medications_repository.dart';
import '../domain/models.dart';

/// Formulario para crear o editar un medicamento del plan (ticket AGE-402).
/// Al guardar, programa recordatorios locales para las próximas dosis.
class MedicationPlanScreen extends ConsumerStatefulWidget {
  const MedicationPlanScreen(
      {super.key, required this.patientId, this.medicationId});

  final String patientId;
  final String? medicationId;

  @override
  ConsumerState<MedicationPlanScreen> createState() =>
      _MedicationPlanScreenState();
}

class _MedicationPlanScreenState extends ConsumerState<MedicationPlanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _dose = TextEditingController();
  final _instructions = TextEditingController();

  String _unit = 'mg';
  String _form = 'comprimido';
  final List<TimeOfDay> _schedule = [const TimeOfDay(hour: 8, minute: 0)];
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;

  static const _units = ['mg', 'ml', 'g', 'mcg', 'UI', 'gotas'];
  static const _forms = [
    'comprimido',
    'cápsula',
    'jarabe',
    'gotas',
    'inyección',
    'parche',
  ];

  bool _loading = false;
  bool _saving = false;
  bool get _isEdit => widget.medicationId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref
          .read(medicationsRepositoryProvider)
          .listMedications(widget.patientId);
      final med = list.firstWhere((m) => m.id == widget.medicationId,
          orElse: () => throw StateError('not found'));
      _name.text = med.name;
      _dose.text = med.dose;
      _instructions.text = med.instructions ?? '';
      _unit = _units.contains(med.unit) ? med.unit : _units.first;
      _form = _forms.contains(med.form) ? med.form : _forms.first;
      _startDate = med.startDate;
      _endDate = med.endDate;
      _schedule
        ..clear()
        ..addAll(med.schedule.map(_parseTime).whereType<TimeOfDay>());
      if (_schedule.isEmpty) {
        _schedule.add(const TimeOfDay(hour: 8, minute: 0));
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudo cargar el medicamento.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TimeOfDay? _parseTime(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _addTime() async {
    final picked = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (picked != null) setState(() => _schedule.add(picked));
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : (_endDate ?? _startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  /// Frase que resume el remedio: "Losartán 50 mg, a las 08:00 y 20:00,
  /// todos los días desde hoy".
  Future<bool> _confirm(NewMedication data) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            _isEdit ? '¿Guardar los cambios?' : '¿Agregar este remedio nuevo?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(medicationSentence(data),
                key: const Key('medication-sentence'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(
              _isEdit
                  ? 'Los recordatorios de la cuidadora y del adulto mayor se ajustarán a estos datos.'
                  : 'Desde ese momento aparecerá en los recordatorios de la cuidadora y del adulto mayor.',
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Revisar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(_isEdit ? 'Sí, guardar' : 'Sí, agregar')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_schedule.isEmpty) {
      showAppSnackBar(context, 'Agrega al menos un horario.', error: true);
      return;
    }
    final data = NewMedication(
      name: _name.text.trim(),
      dose: _dose.text.trim(),
      unit: _unit,
      form: _form,
      schedule: _schedule.map(_fmt).toList()..sort(),
      instructions: _instructions.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
    );
    // Confirmación en palabras simples: que se note que se carga algo nuevo.
    if (!await _confirm(data)) return;
    setState(() => _saving = true);
    final repo = ref.read(medicationsRepositoryProvider);
    try {
      final med = _isEdit
          ? await repo.updateMedication(
              widget.patientId, widget.medicationId!, data)
          : await repo.createMedication(widget.patientId, data);

      // Tras generar dosis, programa recordatorios locales de las próximas.
      await _scheduleReminders(med);

      ref.invalidate(medicationsProvider);
      ref.invalidate(todayDosesProvider);
      if (mounted) {
        showAppSnackBar(
            context,
            _isEdit
                ? 'Listo: se guardaron los cambios de ${data.name}.'
                : 'Listo: ${data.name} quedó en el plan. Se avisará a la hora de cada toma.');
        context.pop();
      }
    } catch (e) {
      if (mounted) showAppSnackBar(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Programa recordatorios locales para las próximas dosis generadas.
  Future<void> _scheduleReminders(Medication med) async {
    try {
      final doses = await ref
          .read(medicationsRepositoryProvider)
          .listDoses(widget.patientId, date: DateTime.now());
      final now = DateTime.now();
      for (final d in doses) {
        if (d.medicationId != med.id) continue;
        if (d.status != DoseStatus.pending) continue;
        if (d.scheduledAt.isBefore(now)) continue;
        await PushService.instance.scheduleDoseReminder(
          id: d.id.hashCode & 0x7fffffff,
          medicationName: med.name,
          when: d.scheduledAt,
          doseId: d.id,
        );
      }
    } catch (_) {
      // Los recordatorios son best-effort; no bloquean el guardado.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              _isEdit ? 'Cambiar un remedio' : 'Agregar un remedio nuevo')),
      body: _loading
          ? const LoadingView()
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  // Qué se está haciendo, en palabras simples (feedback del equipo).
                  Text(
                    _isEdit
                        ? 'Estás cambiando un remedio que ya está en el plan.'
                        : 'Estás agregando un remedio nuevo al plan de tomas. '
                            'Revisa nombre, cantidad y horarios: así aparecerá en '
                            'los recordatorios de la cuidadora y del adulto mayor.',
                    key: const Key('medication-intro'),
                    style: const TextStyle(fontSize: 16, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  const MedicalDisclaimer(),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Nombre del medicamento'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _dose,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(labelText: 'Dosis'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _unit,
                          decoration:
                              const InputDecoration(labelText: 'Unidad'),
                          items: [
                            for (final u in _units)
                              DropdownMenuItem(value: u, child: Text(u)),
                          ],
                          onChanged: (v) => setState(() => _unit = v ?? _unit),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _form,
                    decoration: const InputDecoration(labelText: 'Forma'),
                    items: [
                      for (final f in _forms)
                        DropdownMenuItem(value: f, child: Text(f)),
                    ],
                    onChanged: (v) => setState(() => _form = v ?? _form),
                  ),
                  const SizedBox(height: 20),
                  Text('Horarios',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _schedule.length; i++)
                        InputChip(
                          label: Text(_fmt(_schedule[i])),
                          avatar: const Icon(Icons.schedule_rounded, size: 18),
                          onDeleted: () =>
                              setState(() => _schedule.removeAt(i)),
                        ),
                      ActionChip(
                        label: const Text('Agregar hora'),
                        avatar: const Icon(Icons.add_rounded, size: 18),
                        onPressed: _addTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _DateField(
                    label: 'Fecha de inicio',
                    value: DateFormat('d MMM yyyy', 'es').format(_startDate),
                    onTap: () => _pickDate(isStart: true),
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    label: 'Fecha de fin (opcional)',
                    value: _endDate == null
                        ? 'Sin fecha de fin'
                        : DateFormat('d MMM yyyy', 'es').format(_endDate!),
                    onTap: () => _pickDate(isStart: false),
                    onClear: _endDate == null
                        ? null
                        : () => setState(() => _endDate = null),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _instructions,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Instrucciones (opcional)',
                        alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(_isEdit
                            ? 'Guardar cambios'
                            : 'Agregar remedio al plan'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear != null
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded), onPressed: onClear)
              : const Icon(Icons.calendar_today_rounded,
                  color: AppColors.textSecondary),
        ),
        child: Text(value),
      ),
    );
  }
}

/// Frase en lenguaje simple de lo que se está agregando, para que la
/// cuidadora y el adulto mayor entiendan el remedio nuevo (feedback del equipo).
String medicationSentence(NewMedication d) {
  String two(int n) => n.toString().padLeft(2, '0');
  String date(DateTime x) => '${two(x.day)}/${two(x.month)}';
  final now = DateTime.now();
  final amount = [d.dose, d.unit].where((p) => p.trim().isNotEmpty).join(' ');
  final times = d.schedule.isEmpty
      ? 'sin horario fijo'
      : d.schedule.length == 1
          ? 'a las ${d.schedule.single}'
          : 'a las ${d.schedule.sublist(0, d.schedule.length - 1).join(', ')} y ${d.schedule.last}';
  final start = d.startDate;
  final from = (start.year == now.year &&
          start.month == now.month &&
          start.day == now.day)
      ? 'desde hoy'
      : 'desde el ${date(start)}';
  final until = d.endDate == null ? '' : ' hasta el ${date(d.endDate!)}';
  return '${d.name} ${amount.isEmpty ? '' : '$amount, '}$times, todos los días $from$until.'
      .replaceAll('  ', ' ');
}
