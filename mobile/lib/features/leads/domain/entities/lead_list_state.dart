import 'lead.dart';
import 'lead_filters.dart';

enum LeadListStatus { initial, loading, refreshing, loadingMore, success, empty, error }

class LeadListState {
  const LeadListState._({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.limit = 20,
    this.searchQuery = '',
    this.errorMessage,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.filters = const LeadFilters.empty(),
  });

  const LeadListState.initial() : this._(status: LeadListStatus.initial);

  final LeadListStatus status;
  final List<Lead> items;
  final int total;
  final int limit;
  final String searchQuery;
  final String? errorMessage;

  // Phase 13 §"Bulk Selection" — `selectionMode` toggles the AppBar/list
  // into a checkbox-driven picker; `selectedIds` is only meaningful
  // while it's on (and is always cleared when it's turned off).
  final bool selectionMode;
  final Set<String> selectedIds;

  // Phase 14 §"Advanced Lead Search, Filters & Saved Views" — centralized
  // here (not screen-local state) so pull-to-refresh, load-more, and a
  // loaded saved view all read/write the one filter set the controller
  // already threads through every list request.
  final LeadFilters filters;

  bool get hasMore => items.length < total;

  LeadListState copyWith({
    LeadListStatus? status,
    List<Lead>? items,
    int? total,
    String? searchQuery,
    String? errorMessage,
    bool clearError = false,
    bool? selectionMode,
    Set<String>? selectedIds,
    LeadFilters? filters,
  }) {
    return LeadListState._(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      limit: limit,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      selectionMode: selectionMode ?? this.selectionMode,
      selectedIds: selectedIds ?? this.selectedIds,
      filters: filters ?? this.filters,
    );
  }
}
