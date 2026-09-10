/// Mirrors the backend's `AICallInsightOut` (backend/app/schemas/ai_insights.py)
/// — one evolving AI analysis per call (Phase 20). `status` drives which
/// fields are meaningful: only `completed` ever has a non-null
/// summary/sentiment/callScore.
enum AiInsightStatus { pending, processing, completed, failed }

AiInsightStatus _parseStatus(String value) => switch (value) {
      'pending' => AiInsightStatus.pending,
      'processing' => AiInsightStatus.processing,
      'completed' => AiInsightStatus.completed,
      'failed' => AiInsightStatus.failed,
      _ => AiInsightStatus.failed,
    };

class AiCallInsight {
  const AiCallInsight({
    required this.id,
    required this.callId,
    required this.status,
    this.transcript,
    this.summary,
    this.sentiment,
    this.actionItems = const [],
    this.callScore,
    this.errorMessage,
    required this.requestedAt,
    this.completedAt,
  });

  factory AiCallInsight.fromJson(Map<String, dynamic> json) => AiCallInsight(
        id: json['id'] as String,
        callId: json['call_id'] as String,
        status: _parseStatus(json['status'] as String),
        transcript: json['transcript'] as String?,
        summary: json['summary'] as String?,
        sentiment: json['sentiment'] as String?,
        actionItems: (json['action_items'] as List? ?? const []).cast<String>(),
        callScore: json['call_score'] as int?,
        errorMessage: json['error_message'] as String?,
        requestedAt: DateTime.parse(json['requested_at'] as String),
        completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
      );

  final String id;
  final String callId;
  final AiInsightStatus status;
  final String? transcript;
  final String? summary;
  final String? sentiment;
  final List<String> actionItems;
  final int? callScore;
  final String? errorMessage;
  final DateTime requestedAt;
  final DateTime? completedAt;
}
