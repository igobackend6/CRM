import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/call_analytics_period.dart';

/// Opens the Day/Week/Month period picker as a bottom sheet and resolves
/// to the chosen period, or null if the user cancels. [now] is injectable
/// so tests don't depend on the real clock.
Future<CallAnalyticsPeriod?> showCallAnalyticsPeriodSheet(
  BuildContext context, {
  required CallAnalyticsPeriod current,
  DateTime? now,
}) {
  return showModalBottomSheet<CallAnalyticsPeriod>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.standard * 1.5))),
    builder: (context) => _PeriodSheet(current: current, now: now ?? DateTime.now()),
  );
}

class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({required this.current, required this.now});

  final CallAnalyticsPeriod current;
  final DateTime now;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late CallAnalyticsPeriod _selected = widget.current;
  late DateTime _visibleMonth = DateTime(widget.current.start.year, widget.current.start.month);
  late int _visibleYear = widget.current.start.year;

  DateTime get _today => DateTime(widget.now.year, widget.now.month, widget.now.day);

  void _switchKind(AnalyticsPeriodKind kind) {
    if (kind == _selected.kind) return;
    setState(() {
      // Keep the same anchor date so flipping tabs doesn't jump the user
      // to a different part of the calendar.
      final anchor = _selected.start;
      _selected = switch (kind) {
        AnalyticsPeriodKind.day => CallAnalyticsPeriod.day(anchor),
        AnalyticsPeriodKind.week => CallAnalyticsPeriod.week(anchor),
        AnalyticsPeriodKind.month => CallAnalyticsPeriod.month(anchor),
      };
      _visibleMonth = DateTime(anchor.year, anchor.month);
      _visibleYear = anchor.year;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Scrollable so the calendar + buttons never overflow on a short
    // screen (landscape, split-screen, or a large system font).
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<AnalyticsPeriodKind>(
              key: const Key('period-kind'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: AnalyticsPeriodKind.day, label: Text('Day')),
                ButtonSegment(value: AnalyticsPeriodKind.week, label: Text('Week')),
                ButtonSegment(value: AnalyticsPeriodKind.month, label: Text('Month')),
              ],
              selected: {_selected.kind},
              onSelectionChanged: (kinds) => _switchKind(kinds.first),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_selected.kind == AnalyticsPeriodKind.month) _buildMonthPicker(context) else _buildDayCalendar(context),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(key: const Key('period-cancel'), onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(key: const Key('period-apply'), onPressed: () => Navigator.of(context).pop(_selected), child: const Text('Apply')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- Day / Week: a month grid ----

  Widget _buildDayCalendar(BuildContext context) {
    final theme = Theme.of(context);
    final first = _visibleMonth;
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Monday-first grid.
    final canGoNext = !DateTime(first.year, first.month + 1).isAfter(_today);

    return Column(
      children: [
        Row(
          children: [
            Text('${monthName(first.month)} ${first.year}', style: theme.textTheme.titleSmall),
            const Spacer(),
            IconButton(
              key: const Key('period-prev'),
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous month',
              onPressed: () => setState(() => _visibleMonth = DateTime(first.year, first.month - 1)),
            ),
            IconButton(
              key: const Key('period-next'),
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next month',
              onPressed: canGoNext ? () => setState(() => _visibleMonth = DateTime(first.year, first.month + 1)) : null,
            ),
          ],
        ),
        Row(
          children: [
            for (final letter in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(child: Text(letter, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.textDim))),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.15,
          children: [
            for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
            for (var day = 1; day <= daysInMonth; day++) _dayCell(context, DateTime(first.year, first.month, day)),
          ],
        ),
      ],
    );
  }

  Widget _dayCell(BuildContext context, DateTime date) {
    final theme = Theme.of(context);
    final isFuture = date.isAfter(_today);
    final selected = _selected;
    final inSelection = switch (selected.kind) {
      AnalyticsPeriodKind.day => selected.start == date,
      AnalyticsPeriodKind.week => !date.isBefore(selected.start) && date.isBefore(selected.end),
      AnalyticsPeriodKind.month => false,
    };

    final Color? background = inSelection ? AppColors.accent : null;
    final Color textColor = inSelection
        ? Colors.white
        : (isFuture ? AppColors.textDim.withValues(alpha: 0.5) : theme.colorScheme.onSurface);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: background ?? Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          key: Key('period-day-${date.day}'),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: isFuture
              ? null
              : () => setState(() {
                    _selected = selected.kind == AnalyticsPeriodKind.week ? CallAnalyticsPeriod.week(date) : CallAnalyticsPeriod.day(date);
                  }),
          child: Center(child: Text('${date.day}', style: theme.textTheme.bodyMedium?.copyWith(color: textColor))),
        ),
      ),
    );
  }

  // ---- Month: a 3 x 4 grid of month names ----

  Widget _buildMonthPicker(BuildContext context) {
    final theme = Theme.of(context);
    final canGoNext = _visibleYear < _today.year;
    return Column(
      children: [
        Row(
          children: [
            Text('$_visibleYear', style: theme.textTheme.titleSmall),
            const Spacer(),
            IconButton(
              key: const Key('period-prev'),
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous year',
              onPressed: () => setState(() => _visibleYear -= 1),
            ),
            IconButton(
              key: const Key('period-next'),
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next year',
              onPressed: canGoNext ? () => setState(() => _visibleYear += 1) : null,
            ),
          ],
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.2,
          children: [
            for (var month = 1; month <= 12; month++) _monthCell(context, month),
          ],
        ),
      ],
    );
  }

  Widget _monthCell(BuildContext context, int month) {
    final theme = Theme.of(context);
    final start = DateTime(_visibleYear, month);
    final isFuture = start.isAfter(_today);
    final inSelection = _selected.start == start;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: inSelection ? AppColors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        child: InkWell(
          key: Key('period-month-$month'),
          borderRadius: BorderRadius.circular(AppRadius.standard),
          onTap: isFuture ? null : () => setState(() => _selected = CallAnalyticsPeriod.month(start)),
          child: Center(
            child: Text(
              monthName(month).substring(0, 3),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: inSelection ? Colors.white : (isFuture ? AppColors.textDim.withValues(alpha: 0.5) : theme.colorScheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
