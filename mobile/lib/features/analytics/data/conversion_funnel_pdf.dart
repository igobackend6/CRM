import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/conversion_funnel_report.dart';

PdfColor _pdf(Color color) => PdfColor.fromInt(color.toARGB32());

/// The app's own bundled Inter (the same file the UI uses), so the PDF
/// matches the app and covers the accented/Cyrillic/Greek characters a
/// workspace's status names may contain — the PDF spec's built-in
/// Helvetica only covers basic Latin. Returns null (and logs) if the font
/// can't be loaded or parsed, in which case the builder falls back to the
/// built-in font rather than failing the download.
Future<pw.Font?> loadPdfBaseFont() async {
  try {
    final data = await rootBundle.load('assets/fonts/Inter.ttf');
    return pw.Font.ttf(data);
  } catch (e) {
    AppLogger.warning('Could not load Inter for the PDF, using the built-in font: $e');
    return null;
  }
}

/// A one-or-more page A4 PDF of the Conversion Funnel: a title block, the
/// three headline figures, then the stage/status table. [font] null uses
/// the built-in Helvetica; [compress] false leaves the page streams
/// readable (only tests turn it off, to assert on the text).
Future<Uint8List> buildConversionFunnelPdf(
  ConversionFunnelReport report, {
  pw.Font? font,
  bool compress = true,
}) async {
  final document = pw.Document(
    compress: compress,
    title: 'Conversion Funnel',
    author: 'Sales CRM',
    theme: font != null ? pw.ThemeData.withFont(base: font, bold: font, italic: font, boldItalic: font) : null,
  );

  final ink = _pdf(AppColors.textHeading);
  final dim = _pdf(AppColors.textDim);
  final accent = _pdf(AppColors.accent);
  final tint = _pdf(AppColors.accentBg);
  final border = _pdf(AppColors.border);

  pw.Widget cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left, PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? ink),
        ),
      );

  pw.Widget figure(String label, int value) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 8),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: border), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('$value', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: ink)),
              pw.SizedBox(height: 2),
              pw.Text(label, style: pw.TextStyle(fontSize: 9, color: dim)),
            ],
          ),
        ),
      );

  String pad(int n) => n.toString().padLeft(2, '0');
  final at = report.generatedAt;
  final generated = '${at.year}-${pad(at.month)}-${pad(at.day)} ${pad(at.hour)}:${pad(at.minute)}';

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(fontSize: 8, color: dim)),
      ),
      build: (context) => [
        pw.Text('Conversion Funnel', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: accent)),
        pw.SizedBox(height: 6),
        pw.Text('${report.scopeLabel}  |  Period: ${report.periodLabel}', style: pw.TextStyle(fontSize: 10, color: ink)),
        pw.Text('Generated: $generated', style: pw.TextStyle(fontSize: 9, color: dim)),
        pw.SizedBox(height: 16),
        pw.Row(
          children: [
            figure('Customers', report.customers),
            figure('In pipeline', report.inPipeline),
            figure('Lost', report.lost),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Text('Funnel by stage', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: ink)),
        pw.SizedBox(height: 2),
        pw.Text('Leads created in the selected period, by their current status.', style: pw.TextStyle(fontSize: 9, color: dim)),
        pw.SizedBox(height: 8),
        if (report.stages.isEmpty)
          pw.Text('No pipeline stages are configured yet.', style: pw.TextStyle(fontSize: 10, color: dim))
        else
          pw.Table(
            border: pw.TableBorder.all(color: border, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(3),
              2: pw.FixedColumnWidth(56),
              3: pw.FixedColumnWidth(56),
            },
            children: [
              pw.TableRow(
                repeat: true,
                decoration: pw.BoxDecoration(color: accent),
                children: [
                  cell('Stage', bold: true, color: PdfColors.white),
                  cell('Status', bold: true, color: PdfColors.white),
                  cell('Leads', bold: true, align: pw.TextAlign.right, color: PdfColors.white),
                  cell('Share', bold: true, align: pw.TextAlign.right, color: PdfColors.white),
                ],
              ),
              for (final row in report.tableRows)
                pw.TableRow(
                  decoration: row.isStageTotal ? pw.BoxDecoration(color: tint) : null,
                  children: [
                    cell(row.stage, bold: row.isStageTotal),
                    cell(row.status, bold: row.isStageTotal),
                    cell(row.leads, bold: row.isStageTotal, align: pw.TextAlign.right),
                    cell(row.share, bold: row.isStageTotal, align: pw.TextAlign.right),
                  ],
                ),
            ],
          ),
      ],
    ),
  );

  return document.save();
}
