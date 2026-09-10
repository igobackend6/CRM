import 'pipeline_column.dart';

enum PipelineStatus { initial, loading, refreshing, success, empty, error }

/// Mirrors `LeadListState`'s shape (Phase 5) — same
/// initial/loading/refreshing/success/empty/error lifecycle, adapted
/// for a board of columns rather than a flat list of leads.
class PipelineState {
  const PipelineState._({
    required this.status,
    this.columns = const [],
    this.searchQuery = '',
    this.errorMessage,
  });

  const PipelineState.initial() : this._(status: PipelineStatus.initial);

  final PipelineStatus status;
  final List<PipelineColumn> columns;
  final String searchQuery;
  final String? errorMessage;

  PipelineState copyWith({
    PipelineStatus? status,
    List<PipelineColumn>? columns,
    String? searchQuery,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PipelineState._(
      status: status ?? this.status,
      columns: columns ?? this.columns,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
