import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/patients_repository.dart';
import '../domain/models.dart';

/// Lista de pacientes del usuario (tarjetas con semáforo).
/// Se recarga al cambiar de cuenta: un usuario nuevo no ve los pacientes de
/// quien usó la app antes en el mismo equipo.
final myPatientsProvider = FutureProvider<List<PatientCard>>((ref) async {
  if (ref.watch(sessionUserIdProvider) == null) return const [];
  return ref.watch(patientsRepositoryProvider).listMyPatients();
});

/// Paciente seleccionado (persistente en la sesión de la app).
/// null hasta que carga la lista; después, el primero por defecto.
class SelectedPatientController extends Notifier<PatientCard?> {
  @override
  PatientCard? build() {
    // Al cambiar de cuenta se olvida el paciente elegido por la anterior.
    ref.watch(sessionUserIdProvider);
    // Auto-selección del primer paciente cuando la lista carga.
    ref.listen(myPatientsProvider, (_, next) {
      next.whenData((patients) {
        if (state == null && patients.isNotEmpty) state = patients.first;
        // Si el seleccionado ya no existe (p. ej. lo quitaron), re-selecciona.
        if (state != null && !patients.any((p) => p.patientId == state!.patientId)) {
          state = patients.isNotEmpty ? patients.first : null;
        }
      });
    });
    // Si la lista de esta cuenta ya estaba cargada, se elige el primero altiro
    // (mientras recarga no se usa el valor anterior: podría ser de otra cuenta).
    final loaded = ref.read(myPatientsProvider);
    if (loaded.isLoading || !loaded.hasValue) return null;
    return loaded.requireValue.firstOrNull;
  }

  void select(PatientCard patient) => state = patient;
}

final selectedPatientProvider =
    NotifierProvider<SelectedPatientController, PatientCard?>(
        SelectedPatientController.new);

/// Detalle del paciente seleccionado.
final selectedPatientDetailProvider = FutureProvider<Patient?>((ref) async {
  final selected = ref.watch(selectedPatientProvider);
  if (selected == null) return null;
  return ref.watch(patientsRepositoryProvider).getPatient(selected.patientId);
});
