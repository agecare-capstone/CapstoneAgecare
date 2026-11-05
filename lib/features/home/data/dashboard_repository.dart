import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/domain/models.dart';
import '../../patients/domain/models.dart';
import '../domain/models.dart';
import '../domain/wellbeing.dart';

abstract class DashboardRepository {
  /// Resumen del día del paciente (semáforo, highlights, adherencia, vitals).
  Future<TodaySummary> todaySummary(String patientId);

  /// Tablero multi-paciente del usuario actual.
  Future<List<PatientCard>> dashboard();

  /// Semáforo de bienestar de las últimas 24 horas (DAC05-177).
  Future<Wellbeing> wellbeing(String patientId);
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------
class DashboardRepositoryHttp implements DashboardRepository {
  DashboardRepositoryHttp(this._api);
  final ApiClient _api;

  @override
  Future<TodaySummary> todaySummary(String patientId) async {
    final data =
        await _api.get<Map<String, dynamic>>('/patients/$patientId/summary/today');
    return TodaySummary.fromJson(data);
  }

  @override
  Future<Wellbeing> wellbeing(String patientId) async {
    final data =
        await _api.get<Map<String, dynamic>>('/patients/$patientId/wellbeing');
    return Wellbeing.fromJson(data);
  }

  @override
  Future<List<PatientCard>> dashboard() async {
    final data = await _api.get<Map<String, dynamic>>('/users/me/dashboard');
    return ((data['items'] ?? []) as List)
        .map((e) => PatientCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------
class DashboardRepositoryMock implements DashboardRepository {
  @override
  Future<TodaySummary> todaySummary(String patientId) async {
    await Future.delayed(const Duration(milliseconds: 350));

    // José: paciente con datos de wearable desactualizados.
    if (patientId == 'p-jose') {
      return TodaySummary(
        wellbeingStatus: WellbeingStatus.attention,
        date: DateTime.now(),
        summary:
            'El wearable de José no envía datos desde hace 3 horas. Revisa que lo tenga puesto y con batería.',
        topReason: 'Wearable sin datos desde hace 3 h',
        activeAlertsCount: 1,
        adherencePct: 50,
        highlights: const [
          SummaryHighlight(iconKey: 'steps', label: 'Pasos', value: '640'),
          SummaryHighlight(iconKey: 'medication', label: 'Medicación', value: '1/2 tomas'),
          SummaryHighlight(iconKey: 'alert', label: 'Alertas', value: '1 activa'),
        ],
        latestVitals: [
          VitalReading(
            type: 'heart_rate',
            label: 'Ritmo cardíaco',
            value: '68',
            unit: 'lpm',
            iconKey: 'heart',
            measuredAt: DateTime.now().subtract(const Duration(hours: 3)),
          ),
          VitalReading(
            type: 'steps',
            label: 'Pasos',
            value: '640',
            iconKey: 'steps',
            measuredAt: DateTime.now().subtract(const Duration(hours: 3)),
          ),
        ],
      );
    }

    // Elena (por defecto): semáforo warning por ritmo cardíaco elevado.
    return TodaySummary(
      wellbeingStatus: WellbeingStatus.warning,
      date: DateTime.now(),
      summary:
          'Elena ha tenido un ritmo cardíaco elevado esta tarde. El resto del día ha estado dentro de lo normal.',
      topReason: 'Ritmo cardíaco elevado esta tarde',
      activeAlertsCount: 1,
      adherencePct: 80,
      highlights: const [
        SummaryHighlight(iconKey: 'heart', label: 'Ritmo máx.', value: '112 lpm'),
        SummaryHighlight(iconKey: 'steps', label: 'Pasos', value: '3.240'),
        SummaryHighlight(iconKey: 'sleep', label: 'Sueño', value: '7 h 10 m'),
        SummaryHighlight(iconKey: 'medication', label: 'Adherencia', value: '80%'),
      ],
      latestVitals: [
        VitalReading(
          type: 'heart_rate',
          label: 'Ritmo cardíaco',
          value: '112',
          unit: 'lpm',
          iconKey: 'heart',
          inRange: false,
          measuredAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        VitalReading(
          type: 'spo2',
          label: 'Oxígeno (SpO2)',
          value: '97',
          unit: '%',
          iconKey: 'spo2',
          measuredAt: DateTime.now().subtract(const Duration(minutes: 25)),
        ),
        VitalReading(
          type: 'steps',
          label: 'Pasos',
          value: '3.240',
          iconKey: 'steps',
          measuredAt: DateTime.now().subtract(const Duration(minutes: 25)),
        ),
      ],
    );
  }

  @override
  Future<Wellbeing> wellbeing(String patientId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // Mismos casos que el resumen del día: Elena en observación y José con
    // una alerta crítica activa.
    if (patientId == 'p-jose') {
      return const Wellbeing(
        status: TrafficLight.critical,
        score: 50,
        summary: 'Requiere atención inmediata. Posible caída de José.',
        reasons: ['Posible caída de José', 'Wearable sin datos desde hace 3 h'],
      );
    }
    return const Wellbeing(
      status: TrafficLight.warning,
      score: 75,
      summary: 'Hay valores para revisar. Ritmo cardíaco fuera de rango.',
      reasons: ['Ritmo cardíaco fuera de rango'],
    );
  }

  @override
  Future<List<PatientCard>> dashboard() async {
    await Future.delayed(const Duration(milliseconds: 350));
    return const [
      PatientCard(
        patientId: 'p-elena',
        fullName: 'Elena Ramírez',
        role: RoleType.family,
        wellbeingStatus: WellbeingStatus.warning,
        activeAlertsCount: 1,
        topReason: 'Ritmo cardíaco elevado esta tarde',
      ),
      PatientCard(
        patientId: 'p-jose',
        fullName: 'José Ramírez',
        role: RoleType.family,
        wellbeingStatus: WellbeingStatus.attention,
        activeAlertsCount: 1,
        topReason: 'Wearable sin datos desde hace 3 h',
      ),
    ];
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  if (AppConfig.useMocks) return DashboardRepositoryMock();
  return DashboardRepositoryHttp(ref.watch(apiClientProvider));
});
