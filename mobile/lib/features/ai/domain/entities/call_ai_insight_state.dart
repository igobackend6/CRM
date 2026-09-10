import 'ai_call_insight.dart';

enum CallAiInsightStatus { initial, loading, loaded, requesting, error }

/// Call Detail's "AI Insight" section state (Phase 20). `insight == null`
/// while `status == loaded` means analysis was never requested for this
/// call yet — the UI shows an "Analyze this call" action, not an error.
class CallAiInsightState {
  const CallAiInsightState._({required this.status, this.insight, this.errorMessage});

  const CallAiInsightState.initial() : this._(status: CallAiInsightStatus.initial);

  final CallAiInsightStatus status;
  final AiCallInsight? insight;
  final String? errorMessage;

  CallAiInsightState copyWith({
    CallAiInsightStatus? status,
    AiCallInsight? insight,
    bool clearInsight = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CallAiInsightState._(
      status: status ?? this.status,
      insight: clearInsight ? null : (insight ?? this.insight),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
