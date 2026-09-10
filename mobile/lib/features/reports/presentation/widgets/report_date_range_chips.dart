import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/report_date_range.dart';

/// Phase 21C §"Date Range Support" — mirrors `DashboardDateRangeChips`
/// exactly (a `Wrap` of `ChoiceChip`s using the existing design system),
/// extended with a "Custom" option that opens the platform date-range
/// picker rather than just toggling a chip.
class ReportDateRangeChips extends StatelessWidget {
  const ReportDateRangeChips({super.key, required this.filter, required this.onChanged});

  final ReportDateFilter filter;
  final ValueChanged<ReportDateFilter> onChanged;

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final initial = filter.customSince != null && filter.customUntil != null
        ? DateTimeRange(start: filter.customSince!, end: filter.customUntil!.subtract(const Duration(days: 1)))
        : null;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: initial,
    );
    if (picked == null) return;
    // The backend's window is a half-open `[since, until)` — add a day
    // to the picker's inclusive end date so the whole last day counts.
    onChanged(
      ReportDateFilter(range: ReportDateRange.custom, customSince: picked.start, customUntil: picked.end.add(const Duration(days: 1))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        for (final range in ReportDateRange.values)
          ChoiceChip(
            label: Text(range.label),
            selected: filter.range == range,
            onSelected: (_) {
              if (range == ReportDateRange.custom) {
                _pickCustomRange(context);
              } else {
                onChanged(ReportDateFilter(range: range));
              }
            },
          ),
      ],
    );
  }
}
