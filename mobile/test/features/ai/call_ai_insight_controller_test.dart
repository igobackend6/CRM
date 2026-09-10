import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/ai/domain/entities/ai_call_insight.dart';
import 'package:mobile/features/ai/domain/entities/call_ai_insight_state.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';

import '../../helpers/wait_until.dart';
import 'ai_test_container.dart';
import 'fake_ai_insight_repository.dart';

void main() {
  group('CallAiInsightController', () {
    test('loads null when nothing was ever requested for this call', () async {
      final repo = FakeAiInsightRepository()..callInsightToReturn = null;
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callAiInsightControllerProvider('call-1')).close);

      await waitUntil(() => container.read(callAiInsightControllerProvider('call-1')).status == CallAiInsightStatus.loaded);

      expect(container.read(callAiInsightControllerProvider('call-1')).insight, isNull);
    });

    test('loads an existing completed insight', () async {
      final repo = FakeAiInsightRepository()..callInsightToReturn = testAiCallInsight(status: AiInsightStatus.completed);
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callAiInsightControllerProvider('call-1')).close);

      await waitUntil(() => container.read(callAiInsightControllerProvider('call-1')).status == CallAiInsightStatus.loaded);

      final state = container.read(callAiInsightControllerProvider('call-1'));
      expect(state.insight?.status, AiInsightStatus.completed);
      expect(state.insight?.summary, 'Customer requested a quote by Friday.');
    });

    test('a load failure lands in the error state with its message', () async {
      final repo = FakeAiInsightRepository()..getCallInsightError = const NetworkException('Could not reach the server.');
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callAiInsightControllerProvider('call-1')).close);

      await waitUntil(() => container.read(callAiInsightControllerProvider('call-1')).status == CallAiInsightStatus.error);
      expect(container.read(callAiInsightControllerProvider('call-1')).errorMessage, 'Could not reach the server.');
    });

    test('requestAnalysis swaps in the returned insight on success', () async {
      final repo = FakeAiInsightRepository()
        ..callInsightToReturn = null
        ..requestAnalysisResult = testAiCallInsight(status: AiInsightStatus.failed, errorMessage: 'No recording available.');
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callAiInsightControllerProvider('call-1')).close);
      await waitUntil(() => container.read(callAiInsightControllerProvider('call-1')).status == CallAiInsightStatus.loaded);

      final ok = await container.read(callAiInsightControllerProvider('call-1').notifier).requestAnalysis();

      expect(ok, isTrue);
      expect(repo.lastRequestAnalysisCalled, isTrue);
      final state = container.read(callAiInsightControllerProvider('call-1'));
      expect(state.status, CallAiInsightStatus.loaded);
      expect(state.insight?.status, AiInsightStatus.failed);
      expect(state.insight?.errorMessage, 'No recording available.');
    });

    test('requestAnalysis returns false and surfaces an error message on failure', () async {
      final repo = FakeAiInsightRepository()
        ..callInsightToReturn = null
        ..requestAnalysisError = const PermissionDeniedException('Missing permission: calls.update');
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callAiInsightControllerProvider('call-1')).close);
      await waitUntil(() => container.read(callAiInsightControllerProvider('call-1')).status == CallAiInsightStatus.loaded);

      final ok = await container.read(callAiInsightControllerProvider('call-1').notifier).requestAnalysis();

      expect(ok, isFalse);
      expect(container.read(callAiInsightControllerProvider('call-1')).errorMessage, 'Missing permission: calls.update');
    });
  });
}
