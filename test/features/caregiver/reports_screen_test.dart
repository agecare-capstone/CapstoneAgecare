// Reportes de la cuidadora (DAC05-93): rango de fechas y serie diaria,
// exportación a PDF con logo y plan gratuito limitado a 30 días.
import 'dart:io';
import 'dart:typed_data';

import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/auth/application/auth_controller.dart';
import 'package:agecare_app/features/caregiver/data/caregiver_repository.dart';
import 'package:agecare_app/features/caregiver/domain/models.dart';
import 'package:agecare_app/features/caregiver/presentation/report_pdf.dart';
import 'package:agecare_app/features/caregiver/presentation/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('lee el formato del backend (stats + daily)', () {
    final r = CaregiverReport.fromJson({
      'stats': {
        'doses_given': 12,
        'adherence_pct': 85.7,
        'observations': 4,
        'tasks_done': 20,
        'incidents': 1
      },
      'daily': [
        {'date': '2026-11-18', 'doses_given': 6, 'observations': 2, 'tasks_done': 10},
        {'date': '2026-11-19', 'doses_given': 6, 'observations': 2, 'tasks_done': 10},
      ],
    }, from: DateTime(2026, 11, 18), to: DateTime(2026, 11, 19));
    expect(r.tasksDone, 20);
    expect(r.adherencePct, 85.7);
    expect(r.daily.length, 2);
    expect(r.days, 2);
    expect(r.period, 'Del 18/11/2026 al 19/11/2026');
  });

  test('el PDF se genera con el reporte', () async {
    final report = CaregiverReport(
      from: DateTime(2026, 11, 13),
      to: DateTime(2026, 11, 19),
      tasksDone: 30,
      daily: [ReportDay(date: DateTime(2026, 11, 19), tasksDone: 5)],
    );
    final font =
        pw.Font.ttf(File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync().buffer.asByteData());
    final bytes = await buildReportPdfWithLogo(report,
        caregiverName: 'Rosa Pérez', theme: pw.ThemeData.withFont(base: font, bold: font));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  Future<CaregiverRepositoryMock> pump(WidgetTester tester,
      {bool premium = false, List<String>? shared}) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = CaregiverRepositoryMock();
    // upgradePlan espera con Future.delayed: con el reloj falso del test no avanzaría.
    if (premium) await tester.runAsync(repo.upgradePlan);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        caregiverRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: CaregiverReportsScreen(
          shareFile: (f, name) async {
            expect(f.mimeType, 'application/pdf');
            shared?.add(name);
          },
          // El PDF real se prueba arriba; aquí basta con bytes de ejemplo.
          buildPdf: (r, n) async => Uint8List.fromList('%PDF-1.4'.codeUnits),
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    return repo;
  }

  testWidgets('muestra las métricas de los últimos 7 días', (tester) async {
    await pump(tester);
    expect(find.text('Tareas completadas'), findsOneWidget);
    expect(find.text('Dosis administradas'), findsOneWidget);
    expect(find.textContaining('Del '), findsOneWidget);
  });

  testWidgets('el plan gratuito no ve 90 días y recibe la invitación a Premium', (tester) async {
    await pump(tester);
    await tester.tap(find.text('90 días'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('Más de 30 días es Premium'), findsOneWidget);
  });

  testWidgets('en el plan gratuito exportar PDF invita a Premium', (tester) async {
    final shared = <String>[];
    await pump(tester, shared: shared);
    await tester.tap(find.byKey(const Key('export-pdf')));
    await tester.pumpAndSettle();
    expect(find.text('Exportar PDF es Premium'), findsOneWidget);
    expect(shared, isEmpty);
  });

  testWidgets('con Premium se ven 90 días y se comparte el PDF', (tester) async {
    final shared = <String>[];
    await pump(tester, premium: true, shared: shared);
    await tester.tap(find.text('90 días'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('Más de 30 días es Premium'), findsNothing);

    await tester.tap(find.byKey(const Key('export-pdf')));
    await tester.pumpAndSettle();
    expect(shared.single, startsWith('reporte-agecare-'));
    expect(shared.single, endsWith('.pdf'));
  });
}
