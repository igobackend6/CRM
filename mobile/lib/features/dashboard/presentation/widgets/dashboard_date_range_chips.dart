import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/dashboard_date_range.dart';

/// Phase 17 §"Date Range" — mirrors `ActivityFilterChips`
/// (core/widgets/activity_filter_chips.dart) exactly: a `Wrap` of
/// `ChoiceChip`s, one per enum value, using the existing design system
/// rather than a new filter control.
class DashboardDateRangeChips extends StatelessWidget {
  const DashboardDateRangeChips({super.key, required this.selected, required this.onChanged});

  final DashboardDateRange selected;
  final ValueChanged<DashboardDateRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        for (final range in DashboardDateRange.values)
          ChoiceChip(
            label: Text(range.label),
            selected: selected == range,
            onSelected: (_) => onChanged(range),
          ),
      ],
    );
  }
}
