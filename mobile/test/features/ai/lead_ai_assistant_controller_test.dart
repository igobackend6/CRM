import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/ai/domain/entities/ai_assistant_answer.dart';
import 'package:mobile/features/ai/domain/entities/lead_ai_assistant_state.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';

import 'ai_test_container.dart';
import 'fake_ai_insight_repository.dart';

void main() {
  group('LeadAiAssistantController', () {
    test('starts idle', () async {
      final container = await buildAiTestContainer();
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadAiAssistantControllerProvider('l1')).close);

      expect(container.read(leadAiAssistantControllerProvider('l1')).status, LeadAiAssistantStatus.idle);
    });

    test('ask reports the unavailable state when no provider is configured', () async {
      final repo = FakeAiInsightRepository()
        ..askResult = const AiAssistantAnswer(available: false, message: 'The AI assistant is not available yet.');
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadAiAssistantControllerProvider('l1')).close);

      await container.read(leadAiAssistantControllerProvider('l1').notifier).ask('What does this customer need?');

      final state = container.read(leadAiAssistantControllerProvider('l1'));
      expect(state.status, LeadAiAssistantStatus.unavailable);
      expect(state.message, 'The AI assistant is not available yet.');
      expect(repo.lastAskedQuestion, 'What does this customer need?');
    });

    test('ask shows the answer when the assistant is available', () async {
      final repo = FakeAiInsightRepository()
        ..askResult = const AiAssistantAnswer(available: true, answer: 'They want a quote by Friday.');
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadAiAssistantControllerProvider('l1')).close);

      await container.read(leadAiAssistantControllerProvider('l1').notifier).ask('What do they need?');

      final state = container.read(leadAiAssistantControllerProvider('l1'));
      expect(state.status, LeadAiAssistantStatus.answered);
      expect(state.answer, 'They want a quote by Friday.');
    });

    test('a network failure lands in the error state', () async {
      final repo = FakeAiInsightRepository()..askError = const NetworkException('Could not reach the server.');
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadAiAssistantControllerProvider('l1')).close);

      await container.read(leadAiAssistantControllerProvider('l1').notifier).ask('hi');

      final state = container.read(leadAiAssistantControllerProvider('l1'));
      expect(state.status, LeadAiAssistantStatus.error);
      expect(state.message, 'Could not reach the server.');
    });

    test('ask ignores a blank question', () async {
      final repo = FakeAiInsightRepository();
      final container = await buildAiTestContainer(aiInsightRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadAiAssistantControllerProvider('l1')).close);

      await container.read(leadAiAssistantControllerProvider('l1').notifier).ask('   ');

      expect(container.read(leadAiAssistantControllerProvider('l1')).status, LeadAiAssistantStatus.idle);
      expect(repo.lastAskedQuestion, isNull);
    });
  });
}
