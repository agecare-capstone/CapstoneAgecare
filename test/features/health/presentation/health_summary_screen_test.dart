// Resumen de salud de 30/60/90 días (feedback del equipo): promedios,
// mínimos y máximos por vital, y porcentaje de remedios tomados a tiempo.
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/health/data/vitals_repository.dart';
import 'package:agecare_app/features/health/domain/models.dart';
import 'package:agecare_app/features/health/presentation/health_summary_screen.dart';
import 'package:agecare_app/features/medications/data/medications_repository.dart';
import 'package:agecare_app/features/patients/data/patients_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Devuelve series fijas y anota cuántos días se pidieron.
class _Vitals extends VitalsRepositoryMock {
  final requestedDays = <int>[];

  @override
  Future<VitalSeries> getSeries(String patientId, VitalType type,
      {required DateTime from,
      required DateTime to,
      String granularity = 'day'}) async {
    requestedDays.add(to.difference(from).inDays);
    final day = DateTime(2026, 11, 1);
    VitalPoint p(double v, double lo, double hi) =>
        VitalPoint(ts: day, value: v, min: lo, max: hi);
    final points = switch (type) {
      VitalType.heartRate => [p(70, 60, 90), p(80, 65, 120)],
      VitalType.spo2 => [p(97, 94, 99), p(95, 91, 98)],
      VitalType.steps => [p(3000, 3000, 3000), p(5000, 5000, 5000)],
      _ => <VitalPoint>[],
    };
    return VitalSeries(type: type, points: points);
  }
}

void main() {
  Future<_Vitals> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vitals = _Vitals();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        patientsRepositoryProvider.overrideWithValue(PatientsRepositoryMock()),
        vitalsRepositoryProvider.overrideWithValue(vitals),
        medicationsRepositoryProvider
            .overrideWithValue(MedicationsRepositoryMock()),
      ],
      child: MaterialApp(
          theme: AppTheme.light(), home: const HealthSummaryScreen()),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    return vitals;
  }

  test('PeriodStat calcula promedio, mínimo y máximo', () {
    final s = PeriodStat.of(VitalSeries(type: VitalType.heartRate, points: [
      VitalPoint(ts: DateTime(2026), value: 70, min: 60, max: 90),
      VitalPoint(ts: DateTime(2026), value: 80, min: 65, max: 120),
    ]));
    expect(s.avg, 75);
    expect(s.min, 60);
    expect(s.max, 120);
    expect(s.days, 2);
    expect(PeriodStat.of(const VitalSeries(type: VitalType.spo2, points: []))
        .hasData, isFalse);
  });

  testWidgets('muestra las métricas de los últimos 30 días', (tester) async {
    final vitals = await pump(tester);
    expect(find.textContaining('últimos 30 días'), findsOneWidget);
    expect(find.text('75 lpm'), findsOneWidget);
    expect(find.text('Mínimo 60 · máximo 120 · 2 días con datos'),
        findsOneWidget);
    expect(find.text('96 %'), findsOneWidget);
    expect(find.text('Valor más bajo: 91 %'), findsOneWidget);
    expect(find.text('4000'), findsOneWidget);
    expect(find.byKey(const Key('metric-adherence')), findsOneWidget);
    expect(find.text('Temperatura'), findsNothing);
    expect(vitals.requestedDays.toSet(), {30});
  });

  testWidgets('al elegir 90 días pide el período más largo', (tester) async {
    final vitals = await pump(tester);
    await tester.tap(find.text('90 días'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.textContaining('últimos 90 días'), findsOneWidget);
    expect(vitals.requestedDays, contains(90));
  });
}
