import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/allocation_range.dart';

/// "Overall / Last 30 Days / Select Range" — the reference's date chips
/// under the Allocations header.
class AllocationRangeChips extends StatelessWidget {
  const AllocationRangeChips({
    super.key,
    required this.selected,
    required this.customLabel,
    required this.onOverall,
    required this.onLast30Days,
    required this.onSelectRange,
  });

  final AllocationRange selected;

  /// Shown on the third chip once a custom range is applied.
  final String customLabel;
  final VoidCallback onOverall;
  final VoidCallback onLast30Days;
  final VoidCallback onSelectRange;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 4, vertical: AppSpacing.sm),
      child: Row(
        children: [
          _RangeChip(key: const Key('range-overall'), label: 'Overall', selected: selected == AllocationRange.overall, onTap: onOverall),
          const SizedBox(width: AppSpacing.sm - 2),
          _RangeChip(key: const Key('range-last-30'), label: 'Last 30 Days', selected: selected == AllocationRange.last30Days, onTap: onLast30Days),
          const SizedBox(width: AppSpacing.sm - 2),
          _RangeChip(
            key: const Key('range-custom'),
            label: selected == AllocationRange.custom ? customLabel : 'Select Range',
            selected: selected == AllocationRange.custom,
            onTap: onSelectRange,
          ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? AppColors.accent : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.standard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.standard),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 4, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.standard),
            border: Border.all(color: selected ? AppColors.accent : theme.colorScheme.outline),
          ),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: selected ? Colors.white : AppColors.textBody,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
