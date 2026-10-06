import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/analytics/data/conversion_funnel_pdf.dart';
import 'package:mobile/features/analytics/domain/conversion_funnel_report.dart';
import 'package:mobile/features/analytics/domain/customer_funnel.dart';

FunnelStage _stage(String stage, String label, Map<String, int> statuses) =>
    FunnelStage(stage: stage, label: label, statuses: [for (final e in statuses.entries) FunnelStatusRow(name: e.key, count: e.value)]);

ConversionFunnelReport _report(List<FunnelStage> stages) => ConversionFunnelReport(
      scopeLabel: 'Team pipeline',
      periodLabel: 'This week',
      generatedAt: DateTime(2026, 9, 24, 13, 5),
      customers: 3,
      inPipeline: 7,
      lost: 1,
      stages: stages,
    );

final _sample = _report([
  _stage('start', 'Start', {'New': 4}),
  _stage('in_progress', 'In progress', {'Contacted': 3, 'Qualified': 1}),
  _stage('closed_won', 'Won', {'Converted': 2}),
]);

/// With the built-in font and no compression the page streams hold the
/// text as plain `(...) Tj` strings, so a test can assert on what the
/// PDF actually says (an embedded TrueType font encodes glyph ids, which
/// can't be read back this way).
Future<String> _readablePdf(ConversionFunnelReport report) async {
  final bytes = await buildConversionFunnelPdf(report, font: null, compress: false);
  return latin1.decode(bytes);
}

/// The words drawn on the pages, in drawing order, joined by spaces. The
/// pdf library emits every word as its own `[(word)]TJ`, and draws a table
/// row's cells left to right, so a row reads back as "Contacted 3 30%".
String _sentence(String stream) => RegExp(r'\[\((.*?)\)\]TJ').allMatches(stream).map((m) => m.group(1)!).join(' ');

Future<String> _pdfSentence(ConversionFunnelReport report) async => _sentence(await _readablePdf(report));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the file', () {
    test('is a real PDF', () async {
      final bytes = await buildConversionFunnelPdf(_sample, font: await loadPdfBaseFont());

      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(latin1.decode(bytes.sublist(bytes.length - 6)).trim(), endsWith('%%EOF'));
      expect(bytes.length, greaterThan(1000));
    });

    test('is also valid with the built-in font (the fallback path)', () async {
      final bytes = await buildConversionFunnelPdf(_sample, font: null);

      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('an empty funnel still produces a PDF', () async {
      final bytes = await buildConversionFunnelPdf(_report(const []), font: null);

      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    });
  });

  group('the bundled Inter font', () {
    test('loads and parses', () async {
      expect(await loadPdfBaseFont(), isNotNull);
    });

    test('a status name with accented and Cyrillic letters builds without error', () async {
      final report = _report([
        _stage('in_progress', 'In progress', {'Négociation': 2, 'Квалифицирован': 1}),
      ]);

      final bytes = await buildConversionFunnelPdf(report, font: await loadPdfBaseFont());

      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    });
  });

  group('the text', () {
    test('has the title, scope, period, timestamp and headline figures', () async {
      final text = await _pdfSentence(_sample);

      expect(text, contains('Conversion Funnel'));
      expect(text, contains('Team pipeline | Period: This week'));
      expect(text, contains('Generated: 2026-09-24 13:05'));
      expect(text, contains('Customers'));
      expect(text, contains('In pipeline'));
      expect(text, contains('Lost'));
      // The figures themselves: 3 customers, 7 in pipeline, 1 lost.
      expect(text, contains('3 Customers'));
      expect(text, contains('7 In pipeline'));
      expect(text, contains('1 Lost'));
    });

    test('has the table header', () async {
      expect(await _pdfSentence(_sample), contains('Stage Status Leads Share'));
    });

    test('draws each stage total row and each status row with its own count and share', () async {
      final text = await _pdfSentence(_sample);

      // 10 leads in all: Start 4 (40%), In progress 4 (40%), Won 2 (20%).
      expect(text, contains('Start All statuses 4 40%'));
      expect(text, contains('New 4 40%'));
      expect(text, contains('In progress All statuses 4 40%'));
      expect(text, contains('Contacted 3 30%'));
      expect(text, contains('Qualified 1 10%'));
      expect(text, contains('Won All statuses 2 20%'));
      expect(text, contains('Converted 2 20%'));
    });

    test('says so when there are no stages, and draws no table', () async {
      final text = await _pdfSentence(_report(const []));

      expect(text, contains('No pipeline stages are configured yet.'));
      expect(text, isNot(contains('All statuses')));
      expect(text, isNot(contains('Stage Status Leads Share')));
    });

    test('numbers its pages', () async {
      expect(await _pdfSentence(_sample), contains('Page 1 of 1'));
    });

    test('a long funnel flows onto further pages and repeats the header row on each', () async {
      final many = _report([
        for (var s = 0; s < 6; s++) _stage('in_progress', 'Stage $s', {for (var i = 0; i < 12; i++) 'Status $s.$i': i}),
      ]);

      final text = await _pdfSentence(many);

      final pages = int.parse(RegExp(r'Page 1 of (\d+)').firstMatch(text)!.group(1)!);
      expect(pages, greaterThanOrEqualTo(2));
      expect(text, contains('Page $pages of $pages'));
      // `repeat: true` — the "Stage Status Leads Share" header is drawn once per page.
      expect('Stage Status Leads Share'.allMatches(text).length, pages);
    });
  });
}
