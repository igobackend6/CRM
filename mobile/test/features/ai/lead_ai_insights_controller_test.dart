import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/ai/domain/entities/lead_ai_insights_state.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';

import '../../helpers/wait_until.dart';
import 'ai_test_container.dart';
import 'fake_ai_insight_repository.dart';

void main() {
  group('LeadAiInsightsController', () {
    test('loads insights across the lead\'s calls', () async {
      final repo = FakeAiInsightRepository()..leadInsightsToReturn = [testAiCallInsight(id: 'i1'), testAiCallInsight(id: 'i2')];
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadAiInsightsControllerProvider('l1')).close);

      await waitUntil(() => container.read(leadAiInsightsControllerProvider('l1')).status == LeadAiInsightsStatus.success);

      expect(container.read(leadAiInsightsControllerProvider('l1')).items, hasLength(2));
    });

    test('an empty result lands in the empty state', () async {
      final repo = FakeAiInsightRepository()..leadInsightsToReturn = [];
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadAiInsightsControllerProvider('l1')).close);

      await waitUntil(() => container.read(leadAiInsightsControllerProvider('l1')).status == LeadAiInsightsStatus.empty);
    });

    test('a failure lands in the error state with its message', () async {
      final repo = FakeAiInsightRepository()..listLeadInsightsError = const NetworkException('Could not reach the server.');
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadAiInsightsControllerProvider('l1')).close);

      await waitUntil(() => container.read(leadAiInsightsControllerProvider('l1')).status == LeadAiInsightsStatus.error);
      expect(container.read(leadAiInsightsControllerProvider('l1')).errorMessage, 'Could not reach the server.');
    });
  });
}
