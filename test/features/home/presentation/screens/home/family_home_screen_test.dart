// Pruebas de Inicio con 1 y con 2+ pacientes (AGE-305 / DAC05-64, DAC05-65).
//
// Con 2 o más pacientes se ve una tarjeta por paciente con su estado y tocarla
// cambia el paciente del semáforo. Con 1 paciente no hay tarjetas: Inicio es de
// ese paciente. Deslizar hacia abajo recarga el semáforo.
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/home/data/dashboard_repository.dart';
import 'package:agecare_app/features/home/domain/wellbeing.dart';
import 'package:agecare_app/features/home/presentation/screens/home/family_home_screen.dart';
import 'package:agecare_app/features/home/presentation/widgets/patients/patient_cards.dart';
import 'package:agecare_app/features/patients/application/patients_providers.dart';
import 'package:agecare_app/features/patients/data/patients_repository.dart';
import 'package:agecare_app/features/patients/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Semáforo distinto por paciente, contando las consultas.
class _Dashboard extends DashboardRepositoryMock {
  final calls = <String>[];

  @override
  Future<Wellbeing> wellbeing(String patientId) async {
    calls.add(patientId);
    return patientId == 'p-jose'
        ? const Wellbeing(
            status: TrafficLight.critical,
            summary: 'Semáforo de José',
            reasons: ['Oxígeno (SpO2) en nivel crítico'])
        : const Wellbeing(
            status: TrafficLight.ok, summary: 'Semáforo de Elena');
  }
}

/// Solo Elena: el caso de un único paciente.
class _OnePatient extends PatientsRepositoryMock {
  @override
  Future<List<PatientCard>> listMyPatients() async =>
      (await super.listMyPatients()).take(1).toList();
}

void main() {
  Future<_Dashboard> pump(
      WidgetTester tester, PatientsRepository patients) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dashboard = _Dashboard();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        patientsRepositoryProvider.overrideWithValue(patients),
        dashboardRepositoryProvider.overrideWithValue(dashboard),
      ],
      child:
          MaterialApp(theme: AppTheme.light(), home: const FamilyHomeScreen()),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    return dashboard;
  }

  testWidgets('con 2 pacientes muestra una tarjeta por paciente con su estado',
      (tester) async {
    await pump(tester, PatientsRepositoryMock());

    expect(find.text(PatientCards.title), findsOneWidget);
    expect(find.byKey(const Key('patient-card-p-elena')), findsOneWidget);
    expect(find.byKey(const Key('patient-card-p-jose')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('patient-card-p-jose')),
            matching: find.text('1 alerta activa')),
        findsOneWidget);
    expect(
        find.bySemanticsLabel('José Ramírez, estado Regular, 1 alerta activa'),
        findsOneWidget);
    // El primero queda seleccionado y el semáforo es el suyo.
    expect(find.text('Semáforo de Elena'), findsOneWidget);
  });

  testWidgets('tocar la tarjeta de otro paciente cambia el semáforo',
      (tester) async {
    final dashboard = await pump(tester, PatientsRepositoryMock());

    await tester.tap(find.byKey(const Key('patient-card-p-jose')));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Con motivo, el semáforo destaca el motivo (Rojo de José).
    expect(find.text('Oxígeno (SpO2) en nivel crítico'), findsOneWidget);
    expect(find.text('Semáforo de Elena'), findsNothing);
    expect(dashboard.calls, containsAllInOrder(['p-elena', 'p-jose']));
    final container = ProviderScope.containerOf(
        tester.element(find.byType(FamilyHomeScreen)));
    expect(container.read(selectedPatientProvider)?.patientId, 'p-jose');
  });

  testWidgets('con 1 paciente no muestra tarjetas y el semáforo es el suyo',
      (tester) async {
    await pump(tester, _OnePatient());

    expect(find.text(PatientCards.title), findsNothing);
    expect(find.byKey(const Key('patient-card-p-elena')), findsNothing);
    expect(find.text('Semáforo de Elena'), findsOneWidget);
  });

  testWidgets('deslizar hacia abajo vuelve a consultar el semáforo',
      (tester) async {
    final dashboard = await pump(tester, PatientsRepositoryMock());
    final before = dashboard.calls.length;

    await tester.fling(
        find.text('Semáforo de Elena'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(dashboard.calls.length, greaterThan(before));
    expect(find.text('Semáforo de Elena'), findsOneWidget);
  });
}
