/// Mirrors the backend's `AIAssistantAnswer` (backend/app/schemas/ai_insights.py).
/// `available == false` is the honest, expected response whenever no AI
/// provider is configured — the UI renders `message`, not an error page.
class AiAssistantAnswer {
  const AiAssistantAnswer({required this.available, this.answer, this.message});

  factory AiAssistantAnswer.fromJson(Map<String, dynamic> json) => AiAssistantAnswer(
        available: json['available'] as bool? ?? false,
        answer: json['answer'] as String?,
        message: json['message'] as String?,
      );

  final bool available;
  final String? answer;
  final String? message;
}
