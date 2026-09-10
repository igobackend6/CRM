import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/ai/data/ai_insight_repository_impl.dart';
import 'package:mobile/features/ai/domain/entities/ai_call_insight.dart';

import 'fake_ai_insight_api_data_source.dart';

Map<String, dynamic> _insightJson({String status = 'completed'}) => {
      'id': 'insight-1',
      'call_id': 'call-1',
      'status': status,
      'provider': null,
      'transcript': status == 'completed' ? 'stub transcript' : null,
      'summary': status == 'completed' ? 'stub summary' : null,
      'sentiment': status == 'completed' ? 'positive' : null,
      'action_items': status == 'completed' ? ['Send quote'] : <String>[],
      'call_score': status == 'completed' ? 82 : null,
      'error_message': status == 'failed' ? 'No recording available.' : null,
      'requested_at': '2026-01-01T00:00:00Z',
      'completed_at': status == 'completed' ? '2026-01-01T00:05:00Z' : null,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

void main() {
  group('AiInsightRepositoryImpl', () {
    test('getCallInsight returns null when nothing requested yet', () async {
      final dataSource = FakeAiInsightApiDataSource()..getCallInsightResponse = null;
      final repo = AiInsightRepositoryImpl(dataSource);

      final insight = await repo.getCallInsight(accessToken: 't', workspaceId: 'w1', callId: 'call-1');

      expect(insight, isNull);
      expect(dataSource.lastCallId, 'call-1');
    });

    test('getCallInsight maps a completed insight', () async {
      final dataSource = FakeAiInsightApiDataSource()..getCallInsightResponse = _insightJson();
      final repo = AiInsightRepositoryImpl(dataSource);

      final insight = await repo.getCallInsight(accessToken: 't', workspaceId: 'w1', callId: 'call-1');

      expect(insight!.status, AiInsightStatus.completed);
      expect(insight.summary, 'stub summary');
      expect(insight.sentiment, 'positive');
      expect(insight.actionItems, ['Send quote']);
      expect(insight.callScore, 82);
    });

    test('getCallInsight maps a failed insight with its error message', () async {
      final dataSource = FakeAiInsightApiDataSource()..getCallInsightResponse = _insightJson(status: 'failed');
      final repo = AiInsightRepositoryImpl(dataSource);

      final insight = await repo.getCallInsight(accessToken: 't', workspaceId: 'w1', callId: 'call-1');

      expect(insight!.status, AiInsightStatus.failed);
      expect(insight.errorMessage, 'No recording available.');
      expect(insight.summary, isNull);
    });

    test('requestCallAnalysis maps the returned insight', () async {
      final dataSource = FakeAiInsightApiDataSource()..requestCallAnalysisResponse = _insightJson(status: 'pending');
      final repo = AiInsightRepositoryImpl(dataSource);

      final insight = await repo.requestCallAnalysis(accessToken: 't', workspaceId: 'w1', callId: 'call-1');

      expect(insight.status, AiInsightStatus.pending);
      expect(dataSource.lastCallId, 'call-1');
    });

    test('listLeadInsights maps every item', () async {
      final dataSource = FakeAiInsightApiDataSource()..listLeadInsightsResponse = [_insightJson(), _insightJson(status: 'failed')];
      final repo = AiInsightRepositoryImpl(dataSource);

      final items = await repo.listLeadInsights(accessToken: 't', workspaceId: 'w1', leadId: 'l1');

      expect(items, hasLength(2));
      expect(items[0].status, AiInsightStatus.completed);
      expect(items[1].status, AiInsightStatus.failed);
      expect(dataSource.lastLeadId, 'l1');
    });

    test('askAssistant maps an available answer', () async {
      final dataSource = FakeAiInsightApiDataSource()
        ..askAssistantResponse = {'available': true, 'answer': 'They want a quote.', 'message': null};
      final repo = AiInsightRepositoryImpl(dataSource);

      final result = await repo.askAssistant(accessToken: 't', workspaceId: 'w1', leadId: 'l1', question: 'What do they need?');

      expect(result.available, isTrue);
      expect(result.answer, 'They want a quote.');
      expect(dataSource.lastQuestion, 'What do they need?');
    });

    test('askAssistant maps an unavailable answer', () async {
      final dataSource = FakeAiInsightApiDataSource();
      final repo = AiInsightRepositoryImpl(dataSource);

      final result = await repo.askAssistant(accessToken: 't', workspaceId: 'w1', leadId: 'l1', question: 'hi');

      expect(result.available, isFalse);
      expect(result.answer, isNull);
    });

    test('a data-source failure propagates as the same AppException', () async {
      final dataSource = FakeAiInsightApiDataSource()..getCallInsightError = const NetworkException('Could not reach the server.');
      final repo = AiInsightRepositoryImpl(dataSource);

      expect(
        () => repo.getCallInsight(accessToken: 't', workspaceId: 'w1', callId: 'call-1'),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
