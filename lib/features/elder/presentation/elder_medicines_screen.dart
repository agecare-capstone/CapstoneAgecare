import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/speech/speech_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/medical_disclaimer.dart';
import '../../medications/domain/models.dart';
import '../application/elder_providers.dart';

/// "Mis remedios" del adulto mayor: lo que tiene que tomar hoy y el resto de
/// la semana, con hora, nombre, cantidad y fecha. Es solo de lectura: los
/// remedios los indica el médico y los cargan la cuidadora o el médico.
class ElderMedicinesScreen extends ConsumerWidget {
  const ElderMedicinesScreen({super.key});

  static const weekDays = 7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(elderDosesProvider(weekDays));
    final speech = ref.read(speechServiceProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const Text('Mis remedios',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
      ),
      body: week.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Message(
          text: 'No pudimos cargar tus remedios.',
          action: 'Intentar de nuevo',
          onAction: () => ref.invalidate(elderDosesProvider(weekDays)),
        ),
        data: (doses) {
          final byDay = _groupByDay(doses);
          final today = _dayOnly(DateTime.now());
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(elderDosesProvider(weekDays)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const Text(
                  'Si algo no coincide con lo que te indicó tu médico, avísale '
                  'a tu familia o a tu cuidadora.',
                  style:
                      TextStyle(fontSize: 20, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                if (doses.isEmpty)
                  const _Message(
                      text: 'No tienes remedios programados esta semana.')
                else
                  for (final entry in byDay.entries) ...[
                    _DayHeader(day: entry.key, isToday: entry.key == today),
                    for (final d in entry.value)
                      _DoseRow(dose: d, speech: speech),
                    const SizedBox(height: 12),
                  ],
                const SizedBox(height: 8),
                const MedicalDisclaimer(forElder: true),
              ],
            ),
          );
        },
      ),
    );
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static Map<DateTime, List<Dose>> _groupByDay(List<Dose> doses) {
    final sorted = [...doses]
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final map = <DateTime, List<Dose>>{};
    for (final d in sorted) {
      map.putIfAbsent(_dayOnly(d.scheduledAt), () => []).add(d);
    }
    return map;
  }
}

/// Fecha en palabras: "Hoy", "Mañana" o "Jueves 12 de noviembre".
String elderDayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(day.year, day.month, day.day).difference(today).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Mañana';
  const days = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo'
  ];
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre'
  ];
  return '${days[day.weekday - 1]} ${day.day} de ${months[day.month - 1]}';
}

/// Cantidad legible: "50 mg", "850 mg"...
String doseAmount(Dose d) {
  final amount = (d.dose ?? '').trim();
  final unit = (d.unit ?? '').trim();
  if (amount.isEmpty) return unit;
  if (unit.isEmpty || amount.toLowerCase().contains(unit.toLowerCase())) {
    return amount;
  }
  return '$amount $unit';
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.isToday});

  final DateTime day;
  final bool isToday;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          elderDayLabel(day),
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: isToday ? AppColors.primaryDark : AppColors.textPrimary,
          ),
        ),
      );
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose, required this.speech});

  final Dose dose;
  final SpeechService speech;

  @override
  Widget build(BuildContext context) {
    final taken = dose.status == DoseStatus.taken;
    final amount = doseAmount(dose);
    final spoken = 'A las ${dose.timeLabel}, ${dose.medicationName}'
        '${amount.isEmpty ? '' : ', $amount'}. ${taken ? 'Ya la tomaste' : dose.status.label}.';
    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      child: Card(
        key: Key('elder-dose-${dose.id}'),
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => speech.speak(spoken),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Text(
                  dose.timeLabel,
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dose.medicationName,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      if (amount.isNotEmpty)
                        Text(amount,
                            style: const TextStyle(
                                fontSize: 20, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Icon(
                  taken ? Icons.check_circle_rounded : Icons.schedule_rounded,
                  size: 32,
                  color: taken ? AppColors.statusOk : AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22)),
            if (action != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: onAction,
                  child: Text(action!, style: const TextStyle(fontSize: 20))),
            ],
          ],
        ),
      );
}
