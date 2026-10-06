import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/report_date_range.dart';

/// Phase 21C §"Date Range Support" — mirrors `DashboardDateRangeChips`
/// exactly (a `Wrap` of `ChoiceChip`s using the existing design system),
/// extended with a "Custom" option that opens the platform date-range
/// picker rather than just toggling a chip.
class ReportDateRangeChips extends StatefulWidget {
  const ReportDateRangeChips({super.key, required this.filter, required this.onChanged, this.singleRow = false});

  final ReportDateFilter filter;
  final ValueChanged<ReportDateFilter> onChanged;

  /// Lays the chips out in one horizontally scrolling line instead of
  /// wrapping onto several rows — for screens where eight chips wrapping
  /// to three rows would eat a fifth of a phone screen. Off by default so
  /// the Reports screen keeps its existing wrapped layout.
  final bool singleRow;

  @override
  State<ReportDateRangeChips> createState() => _ReportDateRangeChipsState();
}

class _ReportDateRangeChipsState extends State<ReportDateRangeChips> {
  // Tags whichever chip is selected so the single-row layout can scroll
  // it into view — without this, the default "All time" (the last chip)
  // starts off-screen and the user can't tell which range is active.
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(ReportDateRangeChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter.range != widget.filter.range) _revealSelected();
  }

  void _revealSelected() {
    if (!widget.singleRow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _selectedKey.currentContext;
      if (!mounted || chipContext == null) return;
      Scrollable.ensureVisible(chipContext, alignment: 0.5, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final filter = widget.filter;
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
    widget.onChanged(
      ReportDateFilter(range: ReportDateRange.custom, customSince: picked.start, customUntil: picked.end.add(const Duration(days: 1))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final range in ReportDateRange.values)
        ChoiceChip(
          key: widget.filter.range == range ? _selectedKey : null,
          label: Text(range.label),
          selected: widget.filter.range == range,
          onSelected: (_) {
            if (range == ReportDateRange.custom) {
              _pickCustomRange(context);
            } else {
              widget.onChanged(ReportDateFilter(range: range));
            }
          },
        ),
    ];

    if (widget.singleRow) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final chip in chips) Padding(padding: const EdgeInsets.only(right: AppSpacing.xs), child: chip),
          ],
        ),
      );
    }
    return Wrap(spacing: AppSpacing.xs, children: chips);
  }
}
