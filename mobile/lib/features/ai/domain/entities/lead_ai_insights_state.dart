import 'ai_call_insight.dart';

enum LeadAiInsightsStatus { initial, loading, success, empty, error }

/// Lead Detail/Customer 360's "Lead Insights" section state (Phase 20)
/// — the aggregated AI insight rows across this lead's own calls.
class LeadAiInsightsState {
  const LeadAiInsightsState._({required this.status, this.items = const [], this.errorMessage});

  const LeadAiInsightsState.initial() : this._(status: LeadAiInsightsStatus.initial);

  final LeadAiInsightsStatus status;
  final List<AiCallInsight> items;
  final String? errorMessage;

  LeadAiInsightsState copyWith({LeadAiInsightsStatus? status, List<AiCallInsight>? items, String? errorMessage}) {
    return LeadAiInsightsState._(
      status: status ?? this.status,
      items: items ?? this.items,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
