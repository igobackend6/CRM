import '../../reports/domain/entities/report_date_range.dart';
import 'call_analytics_period.dart';
import 'customer_funnel.dart';

/// One line of the PDF's funnel table. A stage row carries the stage's
/// total (and is drawn bold/tinted); a status row sits under it.
class FunnelTableRow {
  const FunnelTableRow({required this.stage, required this.status, required this.leads, required this.share, required this.isStageTotal});

  final String stage;
  final String status;
  final String leads;
  final String share;
  final bool isStageTotal;
}

/// Everything the Conversion Funnel PDF shows, in one value — the figures
/// on the Customer Analytics screen at the moment the user tapped
/// download (same scope, same period), plus when it was generated.
class ConversionFunnelReport {
  const ConversionFunnelReport({
    required this.scopeLabel,
    required this.periodLabel,
    required this.generatedAt,
    required this.customers,
    required this.inPipeline,
    required this.lost,
    required this.stages,
  });

  /// "Your pipeline" or "Team pipeline".
  final String scopeLabel;

  /// Human-readable range, e.g. "All time" or "12 Sep 2026 – 20 Sep 2026".
  final String periodLabel;
  final DateTime generatedAt;
  final int customers;
  final int inPipeline;
  final int lost;
  final List<FunnelStage> stages;

  int get totalLeads => stages.fold(0, (sum, stage) => sum + stage.total);

  String _share(int count) => totalLeads > 0 ? '${(count * 100 / totalLeads).round()}%' : '0%';

  /// Header-less table body: for each stage a total row, then its statuses.
  /// "Share" is a slice of all leads in the period (matches the
  /// percentage on each stage card on screen).
  List<FunnelTableRow> get tableRows => [
        for (final stage in stages) ...[
          FunnelTableRow(stage: stage.label, status: 'All statuses', leads: '${stage.total}', share: _share(stage.total), isStageTotal: true),
          for (final row in stage.statuses)
            FunnelTableRow(stage: '', status: row.name, leads: '${row.count}', share: _share(row.count), isStageTotal: false),
        ],
      ];
}

/// What the date filter reads as in the report: the chip's label, or the
/// concrete dates for a custom range (the backend's `until` is exclusive,
/// so the last *included* day is a day earlier).
String describeReportFilter(ReportDateFilter filter) {
  if (filter.range == ReportDateRange.custom && filter.customSince != null && filter.customUntil != null) {
    final last = DateTime(filter.customUntil!.year, filter.customUntil!.month, filter.customUntil!.day - 1);
    return '${_date(filter.customSince!)} – ${_date(last)}';
  }
  return filter.range.label;
}

String _date(DateTime d) => '${d.day} ${monthName(d.month).substring(0, 3)} ${d.year}';

/// `conversion-funnel-this-week-2026-09-24.pdf` — the range and the day it
/// was generated, so two downloads don't collide in Downloads.
String conversionFunnelFileName(ReportDateFilter filter, DateTime now) {
  String pad(int n) => n.toString().padLeft(2, '0');
  final range = filter.range.apiValue.replaceAll('_', '-');
  return 'conversion-funnel-$range-${now.year}-${pad(now.month)}-${pad(now.day)}.pdf';
}
