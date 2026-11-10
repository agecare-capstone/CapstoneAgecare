// Inicio y "Mis remedios" del adulto mayor: agenda del día, remedios de la
// semana en solo lectura y aviso legal.
import 'package:agecare_app/core/speech/speech_service.dart';
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/core/widgets/medical_disclaimer.dart';
import 'package:agecare_app/features/elder/application/elder_providers.dart';
import 'package:agecare_app/features/elder/presentation/elder_home_screen.dart';
import 'package:agecare_app/features/elder/presentation/elder_medicines_screen.dart';
import 'package:agecare_app/features/medications/presentation/medication_plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Voz falsa: guarda lo que se leería en voz alta.
class _FakeSpeech extends Fake implements SpeechService {
  final spoken = <String>[];

  @override
  Future<void> speak(String text, {String voice = 'es-MX-DaliaNeural'}) async =>
      spoken.add(text);
}

void main() {
  Future<_FakeSpeech> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(430, 5200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final speech = _FakeSpeech();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        elderPatientIdProvider.overrideWithValue('p-elena'),
        speechServiceProvider.overrideWithValue(speech),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    return speech;
  }

  testWidgets('el inicio muestra el próximo remedio, las comidas y la cita',
      (tester) async {
    await pump(tester, const ElderHomeScreen());

    expect(find.text('Tu día'), findsOneWidget);
    final medicine = find.byKey(const Key('agenda-medicine'));
    expect(
      find.descendant(
          of: medicine,
          matching: find.textContaining(RegExp('Metformina|Atorvastatina'))),
      findsOneWidget,
    );
    final meals = find.byKey(const Key('agenda-meals'));
    expect(
        find.descendant(
            of: meals, matching: find.textContaining('13:00 · Almuerzo')),
        findsOneWidget);
    expect(
        find.descendant(of: meals, matching: find.textContaining('Desayuno')),
        findsNothing,
        reason: 'el desayuno ya se completó');
    expect(
      find.descendant(
          of: find.byKey(const Key('agenda-appointment')),
          matching: find.textContaining('Control con cardiólogo')),
      findsOneWidget,
    );
    expect(find.byType(MedicalDisclaimer), findsOneWidget);
  });

  testWidgets('"Mis remedios" abre la lista de solo lectura, no el formulario',
      (tester) async {
    final speech = await pump(tester, const ElderHomeScreen());

    await tester.tap(find.text('Mis\nremedios'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.byType(ElderMedicinesScreen), findsOneWidget);
    expect(find.byType(MedicationPlanScreen), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(speech.spoken, contains('Mis remedios de hoy y de la semana'));
  });

  testWidgets(
      'Mis remedios muestra hoy y la semana con hora, nombre y cantidad',
      (tester) async {
    final speech = await pump(tester, const ElderMedicinesScreen());

    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Mañana'), findsOneWidget);
    // 7 días: hoy, mañana y 5 días con su fecha en palabras.
    expect(
        find.textContaining(RegExp(
            r'^(Lunes|Martes|Miércoles|Jueves|Viernes|Sábado|Domingo) \d+ de ')),
        findsNWidgets(5));
    expect(find.text('22:00'), findsNWidgets(7));
    expect(find.text('Atorvastatina'), findsNWidgets(7));
    expect(find.text('20 mg'), findsNWidgets(7));
    expect(find.byType(MedicalDisclaimer), findsOneWidget);

    await tester.tap(find.text('Atorvastatina').first);
    expect(
        speech.spoken.single, startsWith('A las 22:00, Atorvastatina, 20 mg.'));
  });

  test('el aviso legal aclara que no reemplaza a un profesional de la salud',
      () {
    expect(MedicalDisclaimer.text, contains('no reemplaza'));
    expect(MedicalDisclaimer.text, contains('131'));
    expect(MedicalDisclaimer.elderText, contains('no reemplaza a tu médico'));
  });
}
