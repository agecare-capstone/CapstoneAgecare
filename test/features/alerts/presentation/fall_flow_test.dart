// Flujo crítico de caída (AGE-505 / DAC05-84, DAC05-85, DAC05-86).
//
// Criterios: el push de caída abre la pantalla roja; desde ahí se llama a la
// cuidadora o a emergencias (131); resolver exige una nota.
import 'package:agecare_app/app.dart';
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/alerts/data/alerts_repository.dart';
import 'package:agecare_app/features/alerts/presentation/alert_detail_screen.dart';
import 'package:agecare_app/features/auth/domain/models.dart';
import 'package:agecare_app/features/patients/application/patients_providers.dart';
import 'package:agecare_app/features/patients/data/patients_repository.dart';
import 'package:agecare_app/features/patients/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio de demo que registra la nota con que se resuelve.
class _RecordingAlertsRepo extends AlertsRepositoryMock {
  final notes = <String?>[];

  final falseAlarms = <bool>[];

  @override
  Future<void> resolve(String alertId,
      {String? note, bool falseAlarm = false}) {
    notes.add(note);
    falseAlarms.add(falseAlarm);
    return super.resolve(alertId, note: note, falseAlarm: falseAlarm);
  }
}

void main() {
  test('tocar el push de una caída lleva a la pantalla de la alerta', () {
    expect(
      routeForNotification({'type': 'alert', 'alert_id': 'a-fall-1', 'alert_type': 'fall'}),
      '/alerts/a-fall-1',
    );
    expect(routeForNotification({'type': 'dose', 'dose_id': 'd-1'}), '/dose/d-1');
    expect(routeForNotification({'type': 'chat'}), isNull);
  });

  Future<_RecordingAlertsRepo> pumpFall(WidgetTester tester,
      {RoleType role = RoleType.family}) async {
    final repo = _RecordingAlertsRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        alertsRepositoryProvider.overrideWithValue(repo),
        patientsRepositoryProvider.overrideWithValue(PatientsRepositoryMock()),
        myPatientsProvider.overrideWith((ref) async => [
              PatientCard(
                patientId: 'p-elena',
                fullName: 'Elena Ramírez',
                role: role,
                wellbeingStatus: WellbeingStatus.ok,
              ),
            ]),
      ],
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const AlertDetailScreen(alertId: 'a-fall-1')),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('una caída activa muestra la pantalla roja con las dos llamadas',
      (tester) async {
    await pumpFall(tester);

    expect(find.widgetWithText(AppBar, 'Caída detectada'), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, AppColors.critical);

    // La cuidadora de la demo tiene teléfono: el botón queda habilitado.
    final caregiver = find.widgetWithText(FilledButton, 'Llamar a Cuidadora');
    expect(caregiver, findsOneWidget);
    expect(tester.widget<FilledButton>(caregiver).onPressed, isNotNull);
    expect(find.widgetWithText(OutlinedButton, 'Llamar a Emergencias (131)'),
        findsOneWidget);
  });

  testWidgets('la cuidadora no ve "Llamar a Cuidadora", solo el 131',
      (tester) async {
    await pumpFall(tester, role: RoleType.caregiver);

    expect(find.textContaining('Llamar a Cuidadora'), findsNothing);
    expect(find.textContaining('Cuidadora sin teléfono'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Llamar a Emergencias (131)'),
        findsOneWidget);
  });

  testWidgets('resolver una caída exige escribir una nota', (tester) async {
    final repo = await pumpFall(tester);

    await tester.scrollUntilVisible(find.text('Resolver alerta'), 200);
    await tester.tap(find.text('Resolver alerta'));
    await tester.pumpAndSettle();

    // Sin nota, "Resolver" está deshabilitado.
    final confirm = find.widgetWithText(FilledButton, 'Resolver');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Ya está acostada, sin golpes');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(repo.notes, ['Ya está acostada, sin golpes']);
    // Deja que se cierre el aviso de confirmación.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('confirmar falsa alarma exige justificación y queda registrada',
      (tester) async {
    final repo = await pumpFall(tester);

    await tester.scrollUntilVisible(find.text('Confirmar falsa alarma'), 200);
    await tester.tap(find.text('Confirmar falsa alarma'));
    await tester.pumpAndSettle();

    // Sin justificación, "Confirmar" está deshabilitado.
    final confirm = find.widgetWithText(FilledButton, 'Confirmar');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Se le cayó el reloj al velador');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(repo.falseAlarms, [true]);
    expect(repo.notes, ['Se le cayó el reloj al velador']);
    await tester.scrollUntilVisible(
        find.text('Descartada como falsa alarma.'), 200);
    expect(find.text('Descartada como falsa alarma.'), findsOneWidget);
    // Deja que se cierre el aviso de confirmación.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
