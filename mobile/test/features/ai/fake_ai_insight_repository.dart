import 'package:mobile/features/ai/domain/entities/ai_assistant_answer.dart';
import 'package:mobile/features/ai/domain/entities/ai_call_insight.dart';
import 'package:mobile/features/ai/domain/repositories/ai_insight_repository.dart';

AiCallInsight testAiCallInsight({
  String id = 'insight-1',
  String callId = 'call-1',
  AiInsightStatus status = AiInsightStatus.completed,
  String? summary = 'Customer requested a quote by Friday.',
  String? sentiment = 'positive',
  List<String> actionItems = const ['Send quote by Friday'],
  int? callScore = 82,
  String? errorMessage,
  DateTime? requestedAt,
}) =>
    AiCallInsight(
      id: id,
      callId: callId,
      status: status,
      summary: status == AiInsightStatus.completed ? summary : null,
      sentiment: status == AiInsightStatus.completed ? sentiment : null,
      actionItems: status == AiInsightStatus.completed ? actionItems : const [],
      callScore: status == AiInsightStatus.completed ? callScore : null,
      errorMessage: errorMessage,
      requestedAt: requestedAt ?? DateTime.utc(2026, 1, 1),
      completedAt: status == AiInsightStatus.completed ? DateTime.utc(2026, 1, 1, 0, 5) : null,
    );

/// A safe, inert default for every screen test that embeds
/// `CallAiInsightSection`/`LeadAiSection` but isn't itself testing AI
/// behavior — never requested, so the section renders its "Analyze"/
/// empty-state prompt without any network call. See
/// call_ai_insight_section_test.dart/lead_ai_section_test.dart for the
/// actual AI-behavior tests.
class FakeAiInsightRepository implements AiInsightRepository {
  AiCallInsight? callInsightToReturn;
  Object? getCallInsightError;
  AiCallInsight? requestAnalysisResult;
  Object? requestAnalysisError;
  Duration requestAnalysisDelay = Duration.zero;
  List<AiCallInsight> leadInsightsToReturn = const [];
  Object? listLeadInsightsError;
  AiAssistantAnswer askResult = const AiAssistantAnswer(available: false, message: 'The AI assistant is not available yet.');
  Object? askError;

  bool lastRequestAnalysisCalled = false;
  String? lastAskedQuestion;

  @override
  Future<AiCallInsight?> getCallInsight({required String accessToken, required String workspaceId, required String callId}) async {
    if (getCallInsightError != null) throw getCallInsightError!;
    return callInsightToReturn;
  }

  @override
  Future<AiCallInsight> requestCallAnalysis({required String accessToken, required String workspaceId, required String callId}) async {
    lastRequestAnalysisCalled = true;
    if (requestAnalysisDelay > Duration.zero) await Future<void>.delayed(requestAnalysisDelay);
    if (requestAnalysisError != null) throw requestAnalysisError!;
    return requestAnalysisResult ?? testAiCallInsight(callId: callId);
  }

  @override
  Future<List<AiCallInsight>> listLeadInsights({required String accessToken, required String workspaceId, required String leadId}) async {
    if (listLeadInsightsError != null) throw listLeadInsightsError!;
    return leadInsightsToReturn;
  }

  @override
  Future<AiAssistantAnswer> askAssistant({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String question,
  }) async {
    lastAskedQuestion = question;
    if (askError != null) throw askError!;
    return askResult;
  }
}
