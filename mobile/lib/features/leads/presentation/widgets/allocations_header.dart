import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/brand_app_bar.dart';
import '../../domain/entities/lead_status.dart';

/// What the header's overflow menu offers besides the four main icons (used by the Customers tab).
enum AllocationsMenuAction { select, importCsv }

/// The brand-gradient top bar with the full set of list controls (matching the reference's layout:
/// a status selector with a shown/total badge on the left; search, filter, pipeline board and more on
/// the right). The Customers tab uses it; Allocations has the plainer [AllocationsTitleHeader].
class AllocationsHeader extends StatelessWidget implements PreferredSizeWidget {
  const AllocationsHeader({
    super.key,
    required this.statuses,
    required this.selectedStatusId,
    required this.shownCount,
    required this.totalCount,
    required this.activeFilterCount,
    required this.searchOpen,
    required this.onStatusSelected,
    required this.onToggleSearch,
    required this.onOpenFilters,
    required this.onOpenPipeline,
    required this.onMenuAction,
    this.searchTooltip = 'Search leads',
  });

  final List<LeadStatus> statuses;

  /// Null = every status.
  final String? selectedStatusId;
  final int shownCount;
  final int? totalCount;
  final int activeFilterCount;
  final bool searchOpen;

  /// Called with the chosen status id, or null for "All".
  final ValueChanged<String?> onStatusSelected;
  final VoidCallback onToggleSearch;
  final VoidCallback onOpenFilters;
  final VoidCallback onOpenPipeline;
  final ValueChanged<AllocationsMenuAction> onMenuAction;

  /// What the search icon is called: "Search leads" or "Search customers".
  final String searchTooltip;

  static const double _barHeight = kBrandAppBarHeight;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight);

  String get _selectedLabel {
    if (selectedStatusId == null) return 'All';
    for (final s in statuses) {
      if (s.id == selectedStatusId) return s.name;
    }
    return 'All';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const foreground = Colors.white;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: brandHeaderDecoration,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: _barHeight,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: PopupMenuButton<String>(
                        key: const Key('allocations-status-selector'),
                        tooltip: 'Filter by status',
                        position: PopupMenuPosition.under,
                        onSelected: (value) => onStatusSelected(value.isEmpty ? null : value),
                        itemBuilder: (context) => [
                          CheckedPopupMenuItem<String>(value: '', checked: selectedStatusId == null, child: const Text('All')),
                          for (final status in statuses)
                            CheckedPopupMenuItem<String>(value: status.id, checked: selectedStatusId == status.id, child: Text(status.name)),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _selectedLabel,
                                key: const Key('allocations-status-label'),
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(color: foreground, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs + 2),
                            Container(
                              key: const Key('allocations-count-badge'),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(AppRadius.standard / 2),
                              ),
                              child: Text(
                                '$shownCount/${totalCount ?? shownCount}',
                                style: theme.textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: foreground),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(searchOpen ? Icons.close : Icons.search, color: foreground),
                    tooltip: searchOpen ? 'Close search' : searchTooltip,
                    onPressed: onToggleSearch,
                  ),
                  IconButton(
                    icon: Badge(
                      label: Text('$activeFilterCount'),
                      isLabelVisible: activeFilterCount > 0,
                      child: const Icon(Icons.filter_list, color: foreground),
                    ),
                    tooltip: 'Filter leads',
                    onPressed: onOpenFilters,
                  ),
                  // Phase 12's pipeline board, as the reference's fourth icon.
                  IconButton(
                    icon: const Icon(Icons.view_column_outlined, color: foreground),
                    tooltip: 'Pipeline view',
                    onPressed: onOpenPipeline,
                  ),
                  PopupMenuButton<AllocationsMenuAction>(
                    icon: const Icon(Icons.more_vert, color: foreground),
                    tooltip: 'More',
                    onSelected: onMenuAction,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: AllocationsMenuAction.select,
                        child: ListTile(leading: Icon(Icons.checklist_outlined), title: Text('Select leads'), contentPadding: EdgeInsets.zero),
                      ),
                      PopupMenuItem(
                        value: AllocationsMenuAction.importCsv,
                        child: ListTile(
                          leading: Icon(Icons.upload_file_outlined),
                          title: Text('Import leads from CSV'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Allocations tab's top bar: the title, and a search icon at its right.
class AllocationsTitleHeader extends StatelessWidget implements PreferredSizeWidget {
  const AllocationsTitleHeader({super.key, required this.searchOpen, required this.onToggleSearch});

  final bool searchOpen;
  final VoidCallback onToggleSearch;

  @override
  Size get preferredSize => const Size.fromHeight(kBrandAppBarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: brandHeaderDecoration,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: kBrandAppBarHeight,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Allocations',
                      key: const Key('allocations-title'),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: Icon(searchOpen ? Icons.close : Icons.search, color: Colors.white),
                    tooltip: searchOpen ? 'Close search' : 'Search leads',
                    onPressed: onToggleSearch,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
