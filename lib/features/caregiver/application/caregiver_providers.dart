import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../patients/application/patients_providers.dart';
import '../data/caregiver_repository.dart';
import '../domain/models.dart';

/// Resumen del día / turno de la cuidadora.
final caregiverTodayProvider = FutureProvider<CaregiverToday>((ref) {
  ref.watch(sessionUserIdProvider); // se recarga al cambiar de cuenta
  return ref.watch(caregiverRepositoryProvider).getToday();
});

/// Tareas del paciente seleccionado.
final patientTasksProvider =
    FutureProvider.autoDispose<List<CareTask>>((ref) async {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return const [];
  return ref.watch(caregiverRepositoryProvider).listTasks(patient.patientId);
});

/// Observaciones del paciente seleccionado.
final observationsProvider =
    FutureProvider.autoDispose<List<Observation>>((ref) async {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return const [];
  return ref
      .watch(caregiverRepositoryProvider)
      .listObservations(patient.patientId);
});

/// Notas de relevo del paciente seleccionado.
final handoverNotesProvider =
    FutureProvider.autoDispose<List<HandoverNote>>((ref) async {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return const [];
  return ref
      .watch(caregiverRepositoryProvider)
      .listHandoverNotes(patient.patientId);
});

/// Plan freemium de la cuidadora.
final caregiverPlanProvider = FutureProvider<CaregiverPlan>((ref) {
  ref.watch(sessionUserIdProvider); // se recarga al cambiar de cuenta
  return ref.watch(caregiverRepositoryProvider).getPlan();
});

/// Reporte de desempeño de la cuidadora.
/// Reporte de los últimos [days] días, hasta hoy (DAC05-93).
final caregiverReportProvider =
    FutureProvider.autoDispose.family<CaregiverReport, int>((ref, days) {
  final now = DateTime.now();
  final to = DateTime(now.year, now.month, now.day);
  final from = to.subtract(Duration(days: days - 1));
  return ref.watch(caregiverRepositoryProvider).getReport(from: from, to: to);
});

/// Perfil profesional de la cuidadora.
final caregiverProfileProvider = FutureProvider<CaregiverProfile>((ref) {
  ref.watch(sessionUserIdProvider); // se recarga al cambiar de cuenta
  return ref.watch(caregiverRepositoryProvider).getProfile();
});
