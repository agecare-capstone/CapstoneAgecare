import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../patients/application/patients_providers.dart';
import '../../../../patients/domain/models.dart';

/// Tarjetas de los pacientes en Inicio (AGE-305 / DAC05-64).
///
/// Con 2 o más pacientes muestra una tarjeta por paciente con su estado
/// (verde, amarillo o rojo) y sus alertas activas, para ver a todos de un
/// vistazo. Tocar una tarjeta cambia el paciente seleccionado, y el semáforo y
/// el resto de Inicio se recargan para ese paciente. Con un solo paciente no
/// muestra nada: Inicio ya es de ese paciente.
class PatientCards extends ConsumerWidget {
  const PatientCards({super.key, required this.patients});

  final List<PatientCard> patients;

  static const title = 'Tus pacientes';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (patients.length < 2) return const SizedBox.shrink();
    final selected = ref.watch(selectedPatientProvider) ?? patients.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: patients.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = patients[i];
              return _PatientTile(
                patient: p,
                selected: p.patientId == selected.patientId,
                onTap: () =>
                    ref.read(selectedPatientProvider.notifier).select(p),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PatientTile extends StatelessWidget {
  const _PatientTile({
    required this.patient,
    required this.selected,
    required this.onTap,
  });

  final PatientCard patient;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = patient.wellbeingStatus;
    final alerts = patient.activeAlertsCount;
    final detail = alerts > 0
        ? '$alerts alerta${alerts == 1 ? '' : 's'} activa${alerts == 1 ? '' : 's'}'
        : status.label;

    return Semantics(
      button: true,
      selected: selected,
      label: '${patient.fullName}, estado ${status.label}'
          '${alerts > 0 ? ', $detail' : ''}',
      excludeSemantics: true,
      child: Material(
        key: Key('patient-card-${patient.patientId}'),
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 156,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(status.icon, color: status.color, size: 26),
                  const Spacer(),
                  Text(
                    patient.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: alerts > 0
                          ? AppColors.critical
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
