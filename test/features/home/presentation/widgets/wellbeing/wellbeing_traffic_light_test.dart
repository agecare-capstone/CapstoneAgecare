// Pruebas del semáforo de bienestar (AGE-305 / DAC05-11, DAC05-177, DAC05-180).
//
// Criterios: sin anomalías el semáforo está en verde; con una lectura anómala
// o una dosis pospuesta pasa a amarillo o rojo con el motivo destacado. Además
// los estados de carga, sin datos y error con reintento.
import 'dart:async';

import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/auth/domain/models.dart';
import 'package:agecare_app/features/home/application/home_providers.dart';
import 'package:agecare_app/features/home/data/dashboard_repository.dart';
import 'package:agecare_app/features/home/domain/wellbeing.dart';
import 'package:agecare_app/features/home/presentation/widgets/wellbeing/wellbeing_traffic_light.dart';
import 'package:agecare_app/features/patients/application/patients_providers.dart';
import 'package:agecare_app/features/patients/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio cuyas respuestas controla cada prueba.
class _FakeDashboardRepo extends DashboardRepositoryMock {
  _FakeDashboardRepo(this.responses);

  /// Una respuesta por llamada, en orden.
  final List<Future<Wellbeing> Function()> responses;
  int calls = 0;

  @override
  Future<Wellbeing> wellbeing(String patientId) => responses[calls++]();
}

class _FixedPatient extends SelectedPatientController {
  @override
  PatientCard? build() => const PatientCard(
        patientId: 'p-elena',
        fullName: 'Elena',
        role: RoleType.family,
        wellbeingStatus: WellbeingStatus.ok,
      );
}

const _green = Wellbeing(
  status: TrafficLight.ok,
  score: 100,
  summary: 'Todos los signos vitales están en rango.',
);
const _yellow = Wellbeing(
  status: TrafficLight.warning,
  score: 75,
  summary: 'Hay valores para revisar. 1 dosis pospuesta.',
  reasons: ['1 dosis pospuesta'],
);
const _red = Wellbeing(
  status: TrafficLight.critical,
  score: 50,
  summary: 'Requiere atención inmediata. Oxígeno (SpO2) en nivel crítico.',
  reasons: ['Oxígeno (SpO2) en nivel crítico'],
);
const _noData = Wellbeing(
  status: TrafficLight.noData,
  summary: 'Sin datos de signos vitales en las últimas 24 horas.',
);

List<Override> _overrides(_FakeDashboardRepo repo) => [
      dashboardRepositoryProvider.overrideWithValue(repo),
      selectedPatientProvider.overrideWith(_FixedPatient.new),
    ];

void main() {
  Future<_FakeDashboardRepo> pump(
      WidgetTester tester, List<Future<Wellbeing> Function()> responses,
      {bool settle = true}) async {
    final repo = _FakeDashboardRepo(responses);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(repo),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Padding(
              padding: EdgeInsets.all(16), child: WellbeingTrafficLight()),
        ),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
    return repo;
  }

  Color lampColor(WidgetTester tester, TrafficLight lamp) {
    final box =
        tester.widget<Container>(find.byKey(ValueKey('lamp-${lamp.apiValue}')));
    return (box.decoration! as BoxDecoration).color!;
  }

  testWidgets('sin anomalías el semáforo está en verde (Estable)',
      (tester) async {
    await pump(tester, [() async => _green]);

    expect(find.text('Estable'), findsOneWidget);
    expect(find.text(_green.summary), findsOneWidget);
    expect(lampColor(tester, TrafficLight.ok), AppColors.statusOk);
    expect(lampColor(tester, TrafficLight.critical),
        isNot(AppColors.statusAttention));
    expect(find.bySemanticsLabel(RegExp('Semáforo de bienestar: Estable')),
        findsOneWidget);
  });

  testWidgets('una dosis pospuesta lo deja en amarillo con el motivo',
      (tester) async {
    await pump(tester, [() async => _yellow]);

    expect(find.text('En observación'), findsOneWidget);
    expect(find.text('1 dosis pospuesta'), findsOneWidget);
    expect(lampColor(tester, TrafficLight.warning), AppColors.statusWarning);
    expect(lampColor(tester, TrafficLight.ok), isNot(AppColors.statusOk));
  });

  testWidgets('una lectura crítica lo deja en rojo con el motivo',
      (tester) async {
    await pump(tester, [() async => _red]);

    expect(find.text('Requiere atención'), findsOneWidget);
    expect(find.text('Oxígeno (SpO2) en nivel crítico'), findsOneWidget);
    expect(lampColor(tester, TrafficLight.critical), AppColors.statusAttention);
    expect(
        find.bySemanticsLabel(RegExp(
            'Semáforo de bienestar: Requiere atención. Oxígeno \\(SpO2\\)')),
        findsOneWidget);
  });

  testWidgets('sin lecturas muestra el estado vacío', (tester) async {
    await pump(tester, [() async => _noData]);

    expect(find.text(WellbeingTrafficLight.emptyText), findsOneWidget);
    expect(find.byKey(const ValueKey('lamp-ok')), findsNothing);
  });

  testWidgets('muestra un indicador mientras carga', (tester) async {
    final pending = Completer<Wellbeing>();
    await pump(tester, [() => pending.future], settle: false);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Cargando el semáforo de bienestar'),
        findsOneWidget);

    pending.complete(_green);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Estable'), findsOneWidget);
  });

  testWidgets('si falla muestra Reintentar y vuelve a consultar',
      (tester) async {
    final repo = await pump(tester, [
      () async => throw Exception('sin conexión'),
      () async => _green,
    ]);

    expect(find.text('No se pudo cargar el semáforo de bienestar.'),
        findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(repo.calls, 2);
    expect(find.text('Estable'), findsOneWidget);
  });

  testWidgets('cumple contraste y tamaño de toque en todos los estados',
      (tester) async {
    final handle = tester.ensureSemantics();
    for (final state in [_green, _yellow, _red, _noData]) {
      await pump(tester, [() async => state]);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    }
    await pump(tester, [() async => throw Exception('x')]);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('en un celular angosto (320 px) no hay overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(tester, [
      () async => const Wellbeing(
            status: TrafficLight.critical,
            summary: 'x',
            reasons: [
              'Presión arterial en nivel crítico durante la medición de la '
                  'tarde, revisar con el médico tratante'
            ],
          ),
    ]);
    expect(tester.takeException(), isNull);
  });

  group('wellbeingProvider', () {
    test('pasa de AsyncLoading a AsyncData', () async {
      final container = ProviderContainer(
          overrides: _overrides(_FakeDashboardRepo([() async => _yellow])));
      addTearDown(container.dispose);
      final states = <AsyncValue<Wellbeing?>>[];
      container.listen(wellbeingProvider, (_, next) => states.add(next),
          fireImmediately: true);

      await container.read(wellbeingProvider.future);

      expect(states.first, isA<AsyncLoading<Wellbeing?>>());
      expect(states.last.value?.status, TrafficLight.warning);
    });

    test('pasa de AsyncLoading a AsyncError si el backend falla', () async {
      final container = ProviderContainer(
          overrides: _overrides(
              _FakeDashboardRepo([() async => throw Exception('500')])));
      addTearDown(container.dispose);
      final states = <AsyncValue<Wellbeing?>>[];
      container.listen(wellbeingProvider, (_, next) => states.add(next),
          fireImmediately: true);

      await expectLater(
          container.read(wellbeingProvider.future), throwsException);

      expect(states.first, isA<AsyncLoading<Wellbeing?>>());
      expect(states.last, isA<AsyncError<Wellbeing?>>());
    });

    test('lee la respuesta del backend', () {
      final w = Wellbeing.fromJson(const {
        'patient_id': 'p-1',
        'status': 'critical',
        'score': 50,
        'summary': 'Requiere atención inmediata.',
        'reasons': ['Posible caída de Elena'],
        'latest_readings': [],
      });
      expect(w.status, TrafficLight.critical);
      expect(w.score, 50);
      expect(w.topReason, 'Posible caída de Elena');
      expect(
          Wellbeing.fromJson(const {'status': 'no_data', 'score': null}).status,
          TrafficLight.noData);
    });
  });
}
