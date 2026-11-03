// Pruebas de la configuración de umbrales de alerta (AGE-507 / DAC05-91,
// DAC05-199, DAC05-196).
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
  Future<_RecordingVitalsRepo> pumpScreen(
      WidgetTester tester, RoleType role) async {
    final repo = _RecordingVitalsRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        vitalsRepositoryProvider.overrideWithValue(repo),
        selectedPatientProvider.overrideWith(() => _FixedPatient(role)),
      ],
      child:
          MaterialApp(theme: AppTheme.light(), home: const ThresholdsScreen()),
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

  testWidgets('el familiar sube la FC máxima a 115 bpm y se guarda',
      (tester) async {
    final repo = await pumpScreen(tester, RoleType.family);

    // Muestra los umbrales actuales.
    expect(find.text('110'), findsOneWidget);
    // Sin cambios, Guardar está deshabilitado.
    expect(
        tester.widget<FilledButton>(saveButton(VitalType.heartRate)).onPressed,
        isNull);

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
    expect(
        again.firstWhere((t) => t.type == VitalType.heartRate).maxValue, 115);
  });

  testWidgets('un mínimo mayor que el máximo no se guarda', (tester) async {
    final repo = await pumpScreen(tester, RoleType.family);

    await tester.enterText(field(VitalType.heartRate, 'Mínimo'), '120');
    await tester.pump();
    await tester.tap(saveButton(VitalType.heartRate));
    await tester.pumpAndSettle();

    expect(
        find.text('El mínimo debe ser menor que el máximo.'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('un mínimo igual al máximo tampoco se guarda (DAC05-199)',
      (tester) async {
    final repo = await pumpScreen(tester, RoleType.family);

    await tester.enterText(field(VitalType.heartRate, 'Mínimo'), '110');
    await tester.pump();
    await tester.tap(saveButton(VitalType.heartRate));
    await tester.pumpAndSettle();

    expect(
        find.text('El mínimo debe ser menor que el máximo.'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('sin mínimo ni máximo no se guarda', (tester) async {
    final repo = await pumpScreen(tester, RoleType.family);

    await tester.enterText(field(VitalType.heartRate, 'Mínimo'), '');
    await tester.enterText(field(VitalType.heartRate, 'Máximo'), '');
    await tester.pump();
    await tester.tap(saveButton(VitalType.heartRate));
    await tester.pumpAndSettle();

    expect(
        find.text('Indica al menos un valor mínimo o máximo.'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  // La lista es perezosa: las tarjetas de abajo no existen hasta hacer scroll.
  Future<void> scrollTo(WidgetTester tester, VitalType type) =>
      tester.scrollUntilVisible(find.byKey(ValueKey(type)), 200,
          scrollable: find.byType(Scrollable).first);

  Finder inCard(VitalType type, Finder matching) =>
      find.descendant(of: find.byKey(ValueKey(type)), matching: matching);

  testWidgets('un valor biológicamente imposible no se guarda (DAC05-196)',
      (tester) async {
    final repo = await pumpScreen(tester, RoleType.family);

    await tester.enterText(field(VitalType.heartRate, 'Mínimo'), '20');
    await tester.pump();
    await tester.tap(saveButton(VitalType.heartRate));
    await tester.pumpAndSettle();

    expect(find.text('Usa valores entre 30 y 250 bpm.'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('el slider ajusta el máximo de la FC (DAC05-196)',
      (tester) async {
    await pumpScreen(tester, RoleType.family);

    final slider = tester.widget<RangeSlider>(
        inCard(VitalType.heartRate, find.byType(RangeSlider)));
    expect(slider.values, const RangeValues(50, 110));
    expect((slider.min, slider.max), (30, 250));

    slider.onChanged!(const RangeValues(50, 121.4));
    await tester.pump();

    expect(
        tester
            .widget<TextField>(field(VitalType.heartRate, 'Máximo'))
            .controller!
            .text,
        '121');
    expect(
        tester.widget<FilledButton>(saveButton(VitalType.heartRate)).onPressed,
        isNotNull);
  });

  testWidgets('la presión guarda sistólica y diastólica (DAC05-196)',
      (tester) async {
    final repo = await pumpScreen(tester, RoleType.family);
    await scrollTo(tester, VitalType.bloodPressure);
    await tester.pumpAndSettle();

    expect(inCard(VitalType.bloodPressure, find.text('Sistólica')),
        findsOneWidget);
    expect(inCard(VitalType.bloodPressure, find.text('Diastólica')),
        findsOneWidget);
    expect(inCard(VitalType.bloodPressure, find.byType(RangeSlider)),
        findsNWidgets(2));

    // Segunda fila = diastólica.
    await tester.enterText(
        field(VitalType.bloodPressure, 'Máximo').at(1), '85');
    await tester.pump();
    await tester.ensureVisible(saveButton(VitalType.bloodPressure));
    await tester.tap(saveButton(VitalType.bloodPressure));
    await tester.pumpAndSettle();

    final saved = repo.saved.single;
    expect(saved.type, VitalType.bloodPressure);
    expect((saved.maxValue, saved.maxSecondary), (140, 85));
  });

  testWidgets('una diastólica de 200 se rechaza (DAC05-196)', (tester) async {
    final repo = await pumpScreen(tester, RoleType.family);
    await scrollTo(tester, VitalType.bloodPressure);

    await tester.enterText(
        field(VitalType.bloodPressure, 'Máximo').at(1), '200');
    await tester.pump();
    await tester.ensureVisible(saveButton(VitalType.bloodPressure));
    await tester.tap(saveButton(VitalType.bloodPressure));
    await tester.pumpAndSettle();

    expect(find.text('Usa valores entre 30 y 150 mmHg (diastólica).'),
        findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('Restablecer carga los valores recomendados (DAC05-196)',
      (tester) async {
    final repo = await pumpScreen(tester, RoleType.family);
    const temp = VitalType.temperature;
    await scrollTo(tester, temp);
    await tester.pumpAndSettle();

    final reset = inCard(temp,
        find.widgetWithText(TextButton, 'Restablecer a valores recomendados'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pump();

    expect(tester.widget<TextField>(field(temp, 'Mínimo')).controller!.text,
        '35.5');
    expect(tester.widget<TextField>(field(temp, 'Máximo')).controller!.text,
        '37.8');

    await tester.tap(saveButton(temp));
    await tester.pumpAndSettle();
    expect(
        (repo.saved.single.minValue, repo.saved.single.maxValue), (35.5, 37.8));
    expect(find.text('Umbral de Temperatura guardado.'), findsOneWidget);
  });

  testWidgets('en un celular (375 px) no hay overflow (DAC05-196)',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, RoleType.family);
    for (final type in editableVitals) {
      await scrollTo(tester, type);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('la cuidadora ve los umbrales pero no puede editarlos',
      (tester) async {
    await pumpScreen(tester, RoleType.caregiver);

    expect(find.textContaining('Solo el familiar o el médico'), findsOneWidget);
    expect(find.text('110'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsNothing);
    expect(find.text('Restablecer a valores recomendados'), findsNothing);
    expect(
        tester
            .widget<RangeSlider>(
                inCard(VitalType.heartRate, find.byType(RangeSlider)))
            .onChanged,
        isNull);
    expect(
        tester.widget<TextField>(field(VitalType.heartRate, 'Máximo')).enabled,
        isFalse);
  });
}
