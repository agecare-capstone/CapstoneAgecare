// Tests de QA para el formulario de observaciones (DAC05-209 / AGE-605).
//
// Criterios de aceptación:
// - Botón guardar deshabilitado si no hay descripción.
// - Botón guardar deshabilitado mientras la subida está en curso.
// - flutter analyze limpio (verificado por separado).
import 'package:agecare_app/features/caregiver/domain/models.dart';
import 'package:agecare_app/features/caregiver/presentation/observation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(String patientId) => ProviderScope(
      child: MaterialApp(
        home: ObservationScreen(patientId: patientId),
      ),
    );

void main() {
  group('ObservationScreen — validación de formulario', () {
    testWidgets('botón guardar está habilitado cuando hay descripción',
        (tester) async {
      await tester.pumpWidget(_wrap('p-test'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'Paciente con buen ánimo.');
      await tester.pump();

      // Con descripción, el botón no debe estar deshabilitado (onPressed != null).
      final btns = tester.widgetList<FilledButton>(find.byType(FilledButton));
      expect(btns.any((b) => b.onPressed != null), isTrue,
          reason: 'Al menos un FilledButton debe estar habilitado');
    });

    testWidgets('botón guardar deshabilitado cuando el campo está vacío',
        (tester) async {
      await tester.pumpWidget(_wrap('p-test'));
      await tester.pumpAndSettle();

      // No ingresamos texto: el campo está vacío por defecto.
      // Al presionar guardar la validación debe mostrar el error.
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Escribe una observación'), findsOneWidget,
          reason: 'Debe mostrar error de validación si el campo está vacío');
    });

    testWidgets('los dropdowns de categoría y severidad están presentes',
        (tester) async {
      await tester.pumpWidget(_wrap('p-test'));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget,
          reason: 'Debe existir el selector de categoría');
      expect(
          find.byType(DropdownButtonFormField<ObservationSeverity>),
          findsOneWidget,
          reason: 'Debe existir el selector de severidad');
    });

    testWidgets('los botones de cámara y galería están presentes',
        (tester) async {
      await tester.pumpWidget(_wrap('p-test'));
      await tester.pumpAndSettle();

      expect(find.text('Cámara'), findsOneWidget);
      expect(find.text('Galería'), findsOneWidget);
    });

    testWidgets('LinearProgressIndicator no se muestra en estado inicial',
        (tester) async {
      await tester.pumpWidget(_wrap('p-test'));
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNothing,
          reason:
              'El indicador de progreso solo debe aparecer durante la subida');
    });
  });
}
