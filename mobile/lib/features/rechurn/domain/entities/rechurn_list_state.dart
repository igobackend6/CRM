import 'rechurn_filters.dart';
import 'rechurn_lead_card.dart';

enum RechurnListStatus { initial, loading, refreshing, loadingMore, success, empty, error }

/// Mirrors `LeadListState`'s shape (loading/success/empty/error +
/// pull-to-refresh + basic pagination + search + filters), just without
/// Phase 13's bulk-selection fields — out of scope for Phase 19's queue.
class RechurnListState {
  const RechurnListState._({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.limit = 20,
    this.searchQuery = '',
    this.errorMessage,
    this.filters = const RechurnFilters.empty(),
  });

  const RechurnListState.initial() : this._(status: RechurnListStatus.initial);

  final RechurnListStatus status;
  final List<RechurnLeadCard> items;
  final int total;
  final int limit;
  final String searchQuery;
  final String? errorMessage;
  final RechurnFilters filters;

  bool get hasMore => items.length < total;

  RechurnListState copyWith({
    RechurnListStatus? status,
    List<RechurnLeadCard>? items,
    int? total,
    String? searchQuery,
    String? errorMessage,
    bool clearError = false,
    RechurnFilters? filters,
  }) {
    return RechurnListState._(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      limit: limit,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      filters: filters ?? this.filters,
    );
  }
}
