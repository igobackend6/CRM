import 'package:flutter/material.dart';

import '../../features/customer360/domain/entities/activity_filter.dart';
import '../theme/app_spacing.dart';

/// Phase 15 §"Activity Filters" — All/Calls/Follow-ups/Notes/
/// Allocations/Documents, shared by Customer 360's timeline and Lead
/// Detail's activity section.
class ActivityFilterChips extends StatelessWidget {
  const ActivityFilterChips({super.key, required this.selected, required this.onChanged});

  final ActivityFilter selected;
  final ValueChanged<ActivityFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        for (final filter in ActivityFilter.values)
          ChoiceChip(
            label: Text(filter.label),
            selected: selected == filter,
            onSelected: (_) => onChanged(filter),
          ),
      ],
    );
  }
}
