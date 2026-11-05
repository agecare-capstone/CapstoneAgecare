import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../patients/application/patients_providers.dart';
import '../data/dashboard_repository.dart';
import '../domain/models.dart';
import '../domain/wellbeing.dart';

/// Resumen del día del paciente seleccionado.
/// autoDispose: se recalcula al cambiar de paciente y libera memoria al salir.
final todaySummaryProvider =
    FutureProvider.autoDispose<TodaySummary?>((ref) async {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return null;
  return ref.watch(dashboardRepositoryProvider).todaySummary(patient.patientId);
});

/// Semáforo de bienestar (últimas 24 h) del paciente seleccionado (DAC05-177).
final wellbeingProvider = FutureProvider.autoDispose<Wellbeing?>((ref) async {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return null;
  return ref.watch(dashboardRepositoryProvider).wellbeing(patient.patientId);
});
