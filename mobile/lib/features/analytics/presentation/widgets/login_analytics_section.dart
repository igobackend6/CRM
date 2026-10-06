import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../activity/domain/entities/activity_range.dart';
import '../../../activity/domain/entities/activity_summary.dart';
import '../../../activity/presentation/providers/activity_providers.dart';
import '../../domain/format_clock.dart';
import '../../domain/format_talk_time.dart';
import 'analytics_filter_box.dart';

/// Call Analytics → "LOGIN ANALYTICS": how long the member had the app
/// signed in (foreground or background), and how that time split into
/// talk, wrap-up, break and idle. All figures are computed by the backend
/// from stored sessions, breaks and calls — see the Activity service.
///
/// Also where the member starts and ends a break, since break time is one
/// of the figures and only the member knows when they step away.
class LoginAnalyticsSection extends ConsumerStatefulWidget {
  const LoginAnalyticsSection({super.key});

  @override
  ConsumerState<LoginAnalyticsSection> createState() => _LoginAnalyticsSectionState();
}

class _LoginAnalyticsSectionState extends ConsumerState<LoginAnalyticsSection> {
  Timer? _refreshTimer;
  bool _breakBusy = false;

  @override
  void initState() {
    super.initState();
    // Today's login time keeps growing while the screen is open.
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => ref.invalidate(activitySummaryProvider));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleBreak(bool onBreak) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(activityControllerProvider.notifier);
    setState(() => _breakBusy = true);
    try {
      if (onBreak) {
        await controller.endBreak();
      } else {
        await controller.startBreak();
      }
      ref.invalidate(activitySummaryProvider);
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      AppLogger.warning('Could not update the break: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Could not update your break. Please try again.')));
    } finally {
      if (mounted) setState(() => _breakBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = ref.watch(activityRangeProvider);
    final summaryAsync = ref.watch(activitySummaryProvider);
    final status = ref.watch(activityControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('LOGIN ANALYTICS', style: theme.textTheme.labelMedium?.copyWith(color: AppColors.textDim, letterSpacing: 0.8)),
            ),
            AnalyticsFilterBox(
              width: 150,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ActivityRange>(
                  key: const Key('login-range-filter'),
                  value: range,
                  isExpanded: true,
                  items: [for (final r in ActivityRange.values) DropdownMenuItem(value: r, child: Text(r.label))],
                  onChanged: (value) {
                    if (value != null) ref.read(activityRangeProvider.notifier).state = value;
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        summaryAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => AppRetryView(
            message: 'Could not load your login analytics.',
            onRetry: () => ref.invalidate(activitySummaryProvider),
          ),
          data: (summary) => _SummaryCard(summary: summary),
        ),
        const SizedBox(height: AppSpacing.md),
        _BreakControl(status: status, busy: _breakBusy, onToggle: () => _toggleBreak(status.onBreak)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ActivitySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Login Duration', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textBody)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(formatTalkTime(summary.loginSeconds), key: const Key('login-duration'), style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
            ),
            VerticalDivider(width: 1, color: theme.colorScheme.outline),
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            icon: Icons.edit_note,
                            color: AppColors.violet,
                            label: 'Wrap up Time',
                            value: formatTalkTime(summary.wrapUpSeconds),
                            valueKey: const Key('wrap-up-time'),
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            icon: Icons.free_breakfast_outlined,
                            color: AppColors.gold,
                            label: 'Break Time',
                            value: formatTalkTime(summary.breakSeconds),
                            valueKey: const Key('break-time'),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            icon: Icons.hourglass_empty,
                            color: AppColors.pink,
                            label: 'Idle Time',
                            value: formatTalkTime(summary.idleSeconds),
                            valueKey: const Key('idle-time'),
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            icon: Icons.phone_in_talk_outlined,
                            color: AppColors.success,
                            label: 'Total Talk Time',
                            value: formatTalkTime(summary.talkSeconds),
                            valueKey: const Key('talk-time'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.color, required this.label, required this.value, required this.valueKey});

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textBody), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(value, key: valueKey, style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ],
    );
  }
}

class _BreakControl extends StatelessWidget {
  const _BreakControl({required this.status, required this.busy, required this.onToggle});

  final ActivityStatus status;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spinner = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));

    if (!status.onBreak) {
      return OutlinedButton.icon(
        key: const Key('take-break'),
        onPressed: busy ? null : onToggle,
        icon: busy ? spinner : const Icon(Icons.free_breakfast_outlined),
        label: const Text('Take a break'),
      );
    }

    final since = status.breakStartedAt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.goldBg,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.free_breakfast_outlined, color: AppColors.gold),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              since != null ? 'On a break since ${formatClock(since)}' : 'On a break',
              key: const Key('on-break-label'),
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textHeading),
            ),
          ),
          FilledButton(
            key: const Key('end-break'),
            onPressed: busy ? null : onToggle,
            child: busy ? spinner : const Text('End break'),
          ),
        ],
      ),
    );
  }
}
