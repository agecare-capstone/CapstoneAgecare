import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../caregiver/application/caregiver_providers.dart';
import '../../home/application/home_providers.dart';
import '../../patients/application/patients_providers.dart';
import '../data/alerts_repository.dart';
import '../domain/models.dart';

/// Todas las alertas del usuario (activas y ya atendidas).
/// autoDispose: se recarga al volver a entrar al centro de alertas.
final activeAlertsProvider = FutureProvider.autoDispose<List<Alert>>((ref) {
  return ref.watch(alertsRepositoryProvider).listAlerts();
});

/// Número de alertas actualmente activas (para el badge del tab/inicio).
final alertsCountProvider = Provider.autoDispose<int>((ref) {
  final alerts = ref.watch(activeAlertsProvider);
  return alerts.maybeWhen(
    data: (list) => list.where((a) => a.isActive).length,
    orElse: () => 0,
  );
});

/// Refresca las alertas tras una acción (acknowledge/resolve/SOS) y los contadores
/// que las incluyen: "Hoy" de la cuidadora y el resumen y semáforo del paciente.
/// Sin esto, "Hoy" seguía mostrando las mismas alertas después de resolverlas.
void refreshAlerts(Ref ref) {
  ref.invalidate(activeAlertsProvider);
  ref.invalidate(caregiverTodayProvider);
  ref.invalidate(selectedPatientDetailProvider);
  ref.invalidate(todaySummaryProvider);
  ref.invalidate(wellbeingProvider);
}

/// Variante para usar desde widgets con [WidgetRef].
void refreshAlertsFromWidget(WidgetRef ref) {
  ref.invalidate(activeAlertsProvider);
  ref.invalidate(caregiverTodayProvider);
  ref.invalidate(selectedPatientDetailProvider);
  ref.invalidate(todaySummaryProvider);
  ref.invalidate(wellbeingProvider);
}

/// Hora relativa en español ("hace 5 min", "hace 2 h", "hace 3 días").
String alertTimeAgo(DateTime when) {
  final d = DateTime.now().difference(when.toLocal());
  if (d.inSeconds < 60) return 'hace instantes';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  if (d.inDays == 1) return 'ayer';
  return 'hace ${d.inDays} días';
}
