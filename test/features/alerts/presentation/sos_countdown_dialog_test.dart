// Pruebas de la confirmación anti-toque accidental del SOS (AGE-506 / DAC05-88, DAC05-89).
//
// Criterio de aceptación: al presionar SOS se abre una ventana de 3 segundos
// antes de emitir la alerta, y el SOS se puede enviar en menos de 2 toques.
import 'package:agecare_app/features/alerts/presentation/sos_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Abre el diálogo y deja en la lista lo que devuelve al cerrarse.
  Future<List<bool?>> openDialog(WidgetTester tester) async {
    final result = <bool?>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result.add(await showDialog<bool>(
            context: context,
            builder: (_) => const SosCountdownDialog(patientName: 'Rosa'),
          )),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pump();
    return result;
  }

  testWidgets('cuenta 3, 2, 1 y envía el SOS sola (1 toque)', (tester) async {
    final result = await openDialog(tester);

    expect(find.text('Enviando SOS en 3...'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Enviando SOS en 2...'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Enviando SOS en 1...'), findsOneWidget);
    expect(result, isEmpty, reason: 'no envía antes de los 3 segundos');

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(result, [true]);
    expect(find.byType(SosCountdownDialog), findsNothing);
  });

  testWidgets('Cancelar dentro de los 3 segundos no envía nada', (tester) async {
    final result = await openDialog(tester);

    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, [false]);

    // El temporizador quedó detenido: pasado el plazo no se envía nada.
    await tester.pump(const Duration(seconds: 5));
    expect(result, [false]);
  });

  testWidgets('"Enviar ahora" envía sin esperar (2 toques)', (tester) async {
    final result = await openDialog(tester);

    await tester.tap(find.text('Enviar ahora'));
    await tester.pumpAndSettle();
    expect(result, [true]);
  });
}
