import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../leads/domain/entities/lead_status.dart';
import '../../../reports/domain/reports_access.dart';
import '../../../reports/presentation/providers/reports_providers.dart';
import '../../../reports/presentation/widgets/report_date_range_chips.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../data/conversion_funnel_pdf.dart';
import '../../domain/conversion_funnel_report.dart';
import '../../domain/customer_funnel.dart';
import '../providers/analytics_providers.dart';
import '../widgets/analytics_stat_tile.dart';

/// Analytics hub → Customer Analytics: where leads sit in the pipeline,
/// grouped by stage and then status, as a funnel.
///
/// Reuses the existing reports providers rather than adding an endpoint:
/// a manager/admin/ceo sees the workspace-wide pipeline report, everyone
/// else the personal report's own pipeline snapshot — i.e. the widest
/// scope their role is allowed, decided by the same role check the
/// Reports screen uses (the backend still enforces it either way).
class CustomerAnalyticsScreen extends ConsumerWidget {
  const CustomerAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(workspaceControllerProvider).selected?.roleName;
    final teamScope = role != null && canViewTeamReports(role);
    final filter = ref.watch(reportDateFilterProvider);

    return Scaffold(
      appBar: brandAppBar(title: const Text('Customer Analytics')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            child: ReportDateRangeChips(
              singleRow: true,
              filter: filter,
              onChanged: (next) => ref.read(reportDateFilterProvider.notifier).state = next,
            ),
          ),
          Expanded(child: teamScope ? const _TeamFunnel() : const _PersonalFunnel()),
        ],
      ),
    );
  }
}

class _FunnelData {
  const _FunnelData({required this.scopeLabel, required this.counts, required this.customers, required this.active, required this.lost});

  final String scopeLabel;
  final List<({LeadStatus status, int count})> counts;
  final int customers;
  final int active;
  final int lost;
}

class _TeamFunnel extends ConsumerWidget {
  const _TeamFunnel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _FunnelLoader(
      async: ref.watch(pipelineReportProvider).whenData(
            (report) => _FunnelData(
              scopeLabel: 'Team pipeline',
              counts: [for (final item in report.leadsByStatus) (status: item.status, count: item.count)],
              customers: report.convertedCustomers,
              active: report.activeLeads,
              lost: report.lostLeads,
            ),
          ),
      onRetry: () => ref.invalidate(pipelineReportProvider),
    );
  }
}

class _PersonalFunnel extends ConsumerWidget {
  const _PersonalFunnel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _FunnelLoader(
      async: ref.watch(personalReportProvider).whenData(
            (report) => _FunnelData(
              scopeLabel: 'Your pipeline',
              counts: [for (final item in report.pipeline.leadsByStatus) (status: item.status, count: item.count)],
              customers: report.pipeline.customerCount,
              active: report.pipeline.activePipelineCount,
              lost: report.pipeline.lostLeads,
            ),
          ),
      onRetry: () => ref.invalidate(personalReportProvider),
    );
  }
}

class _FunnelLoader extends StatelessWidget {
  const _FunnelLoader({required this.async, required this.onRetry});

  final AsyncValue<_FunnelData> async;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => AppRetryView(message: 'Could not load customer analytics.', onRetry: onRetry),
      data: (data) => _FunnelBody(data: data),
    );
  }
}

Color _stageColor(String stage) => switch (stage) {
      'start' => AppColors.accent2,
      'in_progress' => AppColors.accent,
      'closed_won' => AppColors.success,
      'closed_lost' => AppColors.danger,
      _ => AppColors.cold,
    };

class _FunnelBody extends ConsumerStatefulWidget {
  const _FunnelBody({required this.data});

  final _FunnelData data;

  @override
  ConsumerState<_FunnelBody> createState() => _FunnelBodyState();
}

class _FunnelBodyState extends ConsumerState<_FunnelBody> {
  bool _exporting = false;

  /// Builds the PDF from exactly what's on screen (same scope, same
  /// period) and hands it to the system "save as" dialog.
  Future<void> _exportPdf(List<FunnelStage> stages) async {
    final messenger = ScaffoldMessenger.of(context);
    final filter = ref.read(reportDateFilterProvider);
    final now = DateTime.now();
    final data = widget.data;
    setState(() => _exporting = true);
    try {
      final report = ConversionFunnelReport(
        scopeLabel: data.scopeLabel,
        periodLabel: describeReportFilter(filter),
        generatedAt: now,
        customers: data.customers,
        inPipeline: data.active,
        lost: data.lost,
        stages: stages,
      );
      final bytes = await buildConversionFunnelPdf(report, font: await loadPdfBaseFont());
      final saved = await ref.read(fileSaverProvider).saveBytes(
            fileName: conversionFunnelFileName(filter, now),
            bytes: bytes,
            mimeType: 'application/pdf',
          );
      if (saved) messenger.showSnackBar(const SnackBar(content: Text('Conversion funnel saved.')));
    } catch (e) {
      AppLogger.warning('Could not save the conversion funnel PDF: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Could not save the file.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;
    final stages = buildCustomerFunnel(data.counts);
    final grandTotal = stages.fold<int>(0, (sum, s) => sum + s.total);
    final maxStatusCount = stages.fold<int>(0, (m, s) => s.statuses.fold(m, (m2, r) => r.count > m2 ? r.count : m2));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        SectionHeader(
          icon: Icons.stacked_line_chart,
          iconColor: AppColors.accent,
          title: 'Conversion Funnel',
          action: IconButton(
            key: const Key('export-conversion-funnel'),
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_download_outlined),
            tooltip: 'Download PDF',
            color: AppColors.accent,
            style: IconButton.styleFrom(backgroundColor: AppColors.accentBg),
            onPressed: _exporting ? null : () => _exportPdf(stages),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(data.scopeLabel, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: AnalyticsStatTile(icon: Icons.verified_outlined, color: AppColors.success, value: '${data.customers}', label: 'Customers')),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: AnalyticsStatTile(icon: Icons.trending_up_outlined, color: AppColors.accent, value: '${data.active}', label: 'In pipeline')),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: AnalyticsStatTile(icon: Icons.thumb_down_alt_outlined, color: AppColors.danger, value: '${data.lost}', label: 'Lost')),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(icon: Icons.filter_alt_outlined, title: 'Funnel by stage'),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Leads created in the selected period, by their current status.',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (stages.isEmpty)
          const EmptyStateView(icon: Icons.filter_alt_outlined, message: 'No pipeline stages are configured yet.')
        else
          for (final stage in stages) ...[
            _StageCard(stage: stage, grandTotal: grandTotal, maxStatusCount: maxStatusCount),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.stage, required this.grandTotal, required this.maxStatusCount});

  final FunnelStage stage;
  final int grandTotal;
  final int maxStatusCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _stageColor(stage.stage);
    final share = grandTotal > 0 ? (stage.total * 100 / grandTotal).round() : 0;

    return Container(
      key: Key('funnel-stage-${stage.stage}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(stage.label, style: theme.textTheme.titleSmall)),
              Text('${stage.total} · $share%', style: theme.textTheme.labelLarge?.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final row in stage.statuses)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(row.name, style: theme.textTheme.bodyMedium)),
                      Text('${row.count}', style: theme.textTheme.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: maxStatusCount > 0 ? row.count / maxStatusCount : 0,
                      minHeight: 8,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
