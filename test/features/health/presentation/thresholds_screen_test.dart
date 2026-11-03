// Pruebas de la configuración de umbrales de alerta (AGE-507 / DAC05-91, DAC05-199).
//
// Criterio de aceptación: el familiar ajusta la FC máxima a 115 bpm y ese
// valor queda configurado (el backend dispara las alertas con él). Además,
// la cuidadora solo puede ver los umbrales.
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/auth/domain/models.dart';
import 'package:agecare_app/features/health/data/vitals_repository.dart';
import 'package:agecare_app/features/health/domain/models.dart';
import 'package:agecare_app/features/health/presentation/thresholds_screen.dart';
import 'package:agecare_app/features/patients/application/patients_providers.dart';
import 'package:agecare_app/features/patients/domain/models.dart';
import 'package:flutter/material.dart' hide Threshold;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio de demo que además registra cada umbral guardado.
class _RecordingVitalsRepo extends VitalsRepositoryMock {
  final saved = <Threshold>[];

  @override
  Future<Threshold> updateThreshold(String patientId, Threshold threshold) {
    saved.add(threshold);
    return super.updateThreshold(patientId, threshold);
  }
}

class _FixedPatient extends SelectedPatientController {
  _FixedPatient(this.role);
  final RoleType role;

  @override
  PatientCard? build() => PatientCard(
        patientId: 'p-elena',
        fullName: 'Elena',
        role: role,
        wellbeingStatus: WellbeingStatus.ok,
      );
}

void main() {
  Future<_RecordingVitalsRepo> pumpScreen(WidgetTester tester, RoleType role) async {
    final repo = _RecordingVitalsRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        vitalsRepositoryProvider.overrideWithValue(repo),
        selectedPatientProvider.overrideWith(() => _FixedPatient(role)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const ThresholdsScreen()),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Finder field(VitalType type, String label) => find.descendant(
        of: find.byKey(ValueKey(type)),
        matching: find.widgetWithText(TextField, label),
      );

  Finder saveButton(VitalType type) => find.descendant(
        of: find.byKey(ValueKey(type)),
        matching: find.widgetWithText(FilledButton, 'Guardar'),
      );

  testWidgets('el familiar sube la FC máxima a 115 bpm y se guarda', (tester) async {
    final repo = await pumpScreen(tester, RoleType.family);

    // Muestra los umbrales actuales.
    expect(find.text('110'), findsOneWidget);
    // Sin cambios, Guardar está deshabilitado.
    expect(tester.widget<FilledButton>(saveButton(VitalType.heartRate)).onPressed, isNull);

    await tester.enterText(field(VitalType.heartRate, 'Máximo'), '115');
    await tester.pump();
    await tester.tap(saveButton(VitalType.heartRate));
    await tester.pumpAndSettle();

    expect(repo.saved.single.type, VitalType.heartRate);
    expect(repo.saved.single.minValue, 50);
    expect(repo.saved.single.maxValue, 115);
    expect(find.text('Umbral de Ritmo cardíaco guardado.'), findsOneWidget);

    // Al volver a cargar, el umbral queda en el nuevo valor.
    final again = await repo.getThresholds('p-elena');
    expect(again.firstWhere((t) => t.type == VitalType.heartRate).maxValue, 115);
  });

  testWidgets('un mínimo mayor que el máximo no se guarda', (tester) async {
    final repo = await pumpScreen(tester, RoleType.family);

    await tester.enterText(field(VitalType.heartRate, 'Mínimo'), '120');
    await tester.pump();
    await tester.tap(saveButton(VitalType.heartRate));
    await tester.pumpAndSettle();

    expect(find.text('El mínimo no puede ser mayor que el máximo.'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('la cuidadora ve los umbrales pero no puede editarlos', (tester) async {
    await pumpScreen(tester, RoleType.caregiver);

    expect(find.textContaining('Solo el familiar o el médico'), findsOneWidget);
    expect(find.text('110'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsNothing);
    expect(tester.widget<TextField>(field(VitalType.heartRate, 'Máximo')).enabled, isFalse);
  });
}
