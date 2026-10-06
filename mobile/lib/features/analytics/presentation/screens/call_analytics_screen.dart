import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../reports/domain/entities/call_trends.dart';
import '../../domain/call_analytics_period.dart';
import '../../domain/call_trends_csv.dart';
import '../../domain/chart_axis.dart';
import '../../domain/format_talk_time.dart';
import '../../domain/trend_labels.dart';
import '../providers/analytics_providers.dart';
import '../../../activity/presentation/providers/activity_providers.dart';
import '../widgets/analytics_bar_chart.dart';
import '../widgets/analytics_filter_box.dart';
import '../widgets/analytics_period_sheet.dart';
import '../widgets/login_analytics_section.dart';

/// Analytics hub → Call Analytics. The caller's own calls over a chosen
/// day/week/month, charted per hour or per day, with Overall/Outbound/
/// Inbound and All/Unique switches. All numbers come from
/// `GET /reports/call-trends`; nothing here is computed from data the
/// backend didn't return.
class CallAnalyticsScreen extends ConsumerWidget {
  const CallAnalyticsScreen({super.key});

  Future<void> _pickPeriod(BuildContext context, WidgetRef ref, CallAnalyticsPeriod current) async {
    final picked = await showCallAnalyticsPeriodSheet(context, current: current);
    if (picked != null) ref.read(callAnalyticsPeriodProvider.notifier).state = picked;
  }

  Future<void> _export(BuildContext context, WidgetRef ref, CallTrends trends, CallAnalyticsPeriod period) async {
    final messenger = ScaffoldMessenger.of(context);
    final start = period.start;
    String pad(int n) => n.toString().padLeft(2, '0');
    final fileName = 'call-trends-${period.kind.name}-${start.year}-${pad(start.month)}-${pad(start.day)}.csv';
    try {
      final saved = await ref.read(fileSaverProvider).saveBytes(
            fileName: fileName,
            bytes: Uint8List.fromList(utf8.encode(callTrendsCsv(trends))),
            mimeType: 'text/csv',
          );
      if (saved) messenger.showSnackBar(const SnackBar(content: Text('Call trends saved.')));
    } catch (e) {
      AppLogger.warning('Could not save the call trends export: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Could not save the file.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final period = ref.watch(callAnalyticsPeriodProvider);
    final direction = ref.watch(callTrendDirectionProvider);
    final counting = ref.watch(callCountingProvider);
    final trendsAsync = ref.watch(callTrendsProvider);
    final trends = trendsAsync.valueOrNull;

    return Scaffold(
      appBar: brandAppBar(title: const Text('Call Analytics')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(callTrendsProvider);
          ref.invalidate(activitySummaryProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Row(
              children: [
                Text(
                  'CALL TRENDS',
                  style: theme.textTheme.labelMedium?.copyWith(color: AppColors.textDim, letterSpacing: 0.8),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  key: const Key('export-call-trends'),
                  icon: const Icon(Icons.file_download_outlined),
                  tooltip: 'Download CSV',
                  color: AppColors.accent,
                  style: IconButton.styleFrom(backgroundColor: AppColors.accentBg),
                  // Nothing to export until a load has produced calls.
                  onPressed: trends != null && trends.totalCalls > 0 ? () => _export(context, ref, trends, period) : null,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                AnalyticsFilterBox(
                  width: 112,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<CallCounting>(
                      key: const Key('counting-filter'),
                      value: counting,
                      isExpanded: true,
                      items: [for (final c in CallCounting.values) DropdownMenuItem(value: c, child: Text(c.label))],
                      onChanged: (value) {
                        if (value != null) ref.read(callCountingProvider.notifier).state = value;
                      },
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: InkWell(
                    key: const Key('period-filter'),
                    borderRadius: BorderRadius.circular(AppRadius.standard),
                    onTap: () => _pickPeriod(context, ref, period),
                    child: AnalyticsFilterBox(
                      child: Row(
                        children: [
                          Expanded(child: Text(period.label(DateTime.now()), overflow: TextOverflow.ellipsis)),
                          const Icon(Icons.keyboard_arrow_down, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<CallTrendDirection>(
              key: const Key('direction-filter'),
              showSelectedIcon: false,
              segments: [for (final d in CallTrendDirection.values) ButtonSegment(value: d, label: Text(d.label))],
              selected: {direction},
              onSelectionChanged: (values) => ref.read(callTrendDirectionProvider.notifier).state = values.first,
            ),
            const SizedBox(height: AppSpacing.md),
            trendsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => AppRetryView(
                message: 'Could not load your call analytics.',
                onRetry: () => ref.invalidate(callTrendsProvider),
              ),
              data: (data) => _TrendCards(trends: data, counting: counting),
            ),
            const SizedBox(height: AppSpacing.lg),
            const LoginAnalyticsSection(),
          ],
        ),
      ),
    );
  }
}

class _TrendCards extends StatelessWidget {
  const _TrendCards({required this.trends, required this.counting});

  final CallTrends trends;
  final CallCounting counting;

  @override
  Widget build(BuildContext context) {
    final unique = counting == CallCounting.unique;
    final callValues = [for (final b in trends.buckets) (unique ? b.uniqueLeads : b.calls).toDouble()];
    final callTotal = unique ? trends.uniqueLeads : trends.totalCalls;
    final labels = trendAxisLabels(trends);

    final maxSeconds = trends.buckets.fold<int>(0, (m, b) => b.talkTimeSeconds > m ? b.talkTimeSeconds : m);
    final unit = durationUnitFor(maxSeconds);
    final talkValues = [for (final b in trends.buckets) unit.convert(b.talkTimeSeconds)];

    String plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

    return Column(
      children: [
        _ChartCard(
          title: unique ? 'Unique Leads Called' : 'Total Calls',
          value: '$callTotal',
          hasData: callTotal > 0,
          chartBuilder: (height) => AnalyticsBarChart(
            values: callValues,
            xLabels: labels,
            yLabel: (v) => v.round().toString(),
            describe: (i) =>
                '${bucketTimeLabel(trends.buckets[i], trends.granularity)} · ${plural(callValues[i].round(), unique ? 'lead' : 'call')}',
            color: AppColors.accent,
            height: height,
            wholeNumbers: true,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (unique)
          const _ChartCard.unavailable(
            title: 'Total Talk Time',
            message: 'Talk time is unavailable for unique calls. Switch filter to “All” to view total talk time trends.',
          )
        else
          _ChartCard(
            title: 'Total Talk Time',
            value: formatTalkTime(trends.totalTalkTimeSeconds),
            hasData: trends.totalTalkTimeSeconds > 0,
            chartBuilder: (height) => AnalyticsBarChart(
              values: talkValues,
              xLabels: labels,
              yLabel: unit.label,
              describe: (i) =>
                  '${bucketTimeLabel(trends.buckets[i], trends.granularity)} · ${formatTalkTime(trends.buckets[i].talkTimeSeconds)}',
              color: AppColors.gold,
              height: height,
            ),
          ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required String this.value, required this.hasData, required this.chartBuilder})
      : unavailableMessage = null;

  const _ChartCard.unavailable({required this.title, required String message})
      : value = null,
        hasData = false,
        chartBuilder = null,
        unavailableMessage = message;

  final String title;
  final String? value;
  final bool hasData;
  final Widget Function(double height)? chartBuilder;
  final String? unavailableMessage;

  void _expand(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: brandAppBar(title: Text(title), leading: const CloseButton()),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: chartBuilder!(360),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textDim)),
                    Text(value ?? '—', style: theme.textTheme.headlineSmall),
                  ],
                ),
              ),
              if (chartBuilder != null && hasData)
                IconButton(
                  key: Key('expand-${title.toLowerCase().replaceAll(' ', '-')}'),
                  icon: const Icon(Icons.open_in_full, size: 20),
                  tooltip: 'Expand',
                  onPressed: () => _expand(context),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (unavailableMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Column(
                children: [
                  const Icon(Icons.info_outline, size: 28, color: AppColors.textDim),
                  const SizedBox(height: AppSpacing.sm),
                  Text(unavailableMessage!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textDim)),
                ],
              ),
            )
          else if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.bar_chart_outlined, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: AppSpacing.xs),
                    Text('No data to display', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textDim)),
                  ],
                ),
              ),
            )
          else
            chartBuilder!(180),
        ],
      ),
    );
  }
}
