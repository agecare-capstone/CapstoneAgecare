import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models.dart';

/// Reporte de actividad de la cuidadora en PDF con el logo de AgeCare (DAC05-93).
Future<Uint8List> buildReportPdf(CaregiverReport report, {required String caregiverName}) async {
  final logo =
      pw.MemoryImage((await rootBundle.load('assets/images/logo_icon.png')).buffer.asUint8List());
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  return buildReportPdfWithLogo(report,
      caregiverName: caregiverName,
      logo: logo,
      theme: pw.ThemeData.withFont(base: regular, bold: bold));
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Arma el documento (separado de la carga del logo para poder probarlo).
Future<Uint8List> buildReportPdfWithLogo(CaregiverReport report,
    {required String caregiverName,
    pw.ImageProvider? logo,
    pw.ThemeData? theme,
    DateTime? generatedAt}) {
  const teal = PdfColor.fromInt(0xFF0F766E);
  // Fuente con soporte Unicode (tildes y ñ); la de base del PDF no las tiene.
  final doc =
      pw.Document(title: 'Reporte de actividad AgeCare', author: caregiverName, theme: theme);
  final metrics = <(String, String)>[
    ('Tareas completadas', '${report.tasksDone}'),
    ('Dosis administradas', '${report.dosesGiven}'),
    ('Adherencia a remedios', '${report.adherencePct.round()} %'),
    ('Observaciones', '${report.observations}'),
    ('Incidentes', '${report.incidents}'),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) pw.Image(logo, width: 40, height: 40),
          if (logo != null) pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('AgeCare',
                    style: const pw.TextStyle(
                        fontSize: 20, fontWeight: pw.FontWeight.bold, color: teal)),
                pw.Text('Reporte de actividad de la cuidadora',
                    style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generado el ${_date(generatedAt ?? DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
      build: (ctx) => [
        pw.SizedBox(height: 16),
        pw.Text(caregiverName,
            style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text(report.period, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800)),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Indicador', 'Valor'],
          data: [
            for (final m in metrics) [m.$1, m.$2]
          ],
          headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: teal),
          cellAlignments: {1: pw.Alignment.centerRight},
        ),
        pw.SizedBox(height: 20),
        pw.Text('Actividad por día',
            style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Fecha', 'Tareas', 'Dosis', 'Observaciones'],
          data: [
            for (final d in report.daily)
              [_date(d.date), '${d.tasksDone}', '${d.dosesGiven}', '${d.observations}'],
          ],
          headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {1: pw.Alignment.center, 2: pw.Alignment.center, 3: pw.Alignment.center},
        ),
      ],
    ),
  );
  return doc.save();
}
