enum LeadAiAssistantStatus { idle, asking, answered, unavailable, error }

/// Lead Detail's "AI Assistant" section state (Phase 20) — one stateless
/// question/answer exchange at a time; no persisted conversation history
/// (see AIAssistantService's own docstring for why that's deliberate).
class LeadAiAssistantState {
  const LeadAiAssistantState._({required this.status, this.answer, this.message});

  const LeadAiAssistantState.idle() : this._(status: LeadAiAssistantStatus.idle);

  final LeadAiAssistantStatus status;
  final String? answer;
  final String? message;

  LeadAiAssistantState copyWith({LeadAiAssistantStatus? status, String? answer, String? message}) {
    return LeadAiAssistantState._(status: status ?? this.status, answer: answer ?? this.answer, message: message ?? this.message);
  }
}
