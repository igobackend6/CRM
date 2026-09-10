import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/messaging/domain/entities/conversation_list_state.dart';
import 'package:mobile/features/messaging/presentation/providers/messaging_providers.dart';

import '../../helpers/wait_until.dart';
import 'fake_messaging_repository.dart';
import 'messaging_test_container.dart';

void main() {
  group('ConversationListController', () {
    test('loads conversations on workspace selection', () async {
      final repo = FakeMessagingRepository()
        ..conversationsToReturn = [testConversation(id: 'conv-1')]
        ..conversationsTotalToReturn = 1;
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, conversationListControllerProvider).close);

      await waitUntil(() => container.read(conversationListControllerProvider).status == ConversationListStatus.success);

      expect(container.read(conversationListControllerProvider).items.map((c) => c.id), ['conv-1']);
    });

    test('an empty result lands in the empty state', () async {
      final repo = FakeMessagingRepository();
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, conversationListControllerProvider).close);

      await waitUntil(() => container.read(conversationListControllerProvider).status == ConversationListStatus.empty);
    });

    test('a failure lands in the error state with its message', () async {
      final repo = FakeMessagingRepository()..listConversationsError = const NetworkException('Could not reach the server.');
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, conversationListControllerProvider).close);

      await waitUntil(() => container.read(conversationListControllerProvider).status == ConversationListStatus.error);
      expect(container.read(conversationListControllerProvider).errorMessage, 'Could not reach the server.');
    });

    test('loadMore appends the next page', () async {
      final repo = FakeMessagingRepository()
        ..conversationsToReturn = [testConversation(id: 'conv-1')]
        ..conversationsTotalToReturn = 2;
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, conversationListControllerProvider).close);
      await waitUntil(() => container.read(conversationListControllerProvider).status == ConversationListStatus.success);

      repo.conversationsToReturn = [testConversation(id: 'conv-2')];
      await container.read(conversationListControllerProvider.notifier).loadMore();

      expect(repo.lastConversationsOffset, 1);
      expect(container.read(conversationListControllerProvider).items.map((c) => c.id), ['conv-1', 'conv-2']);
    });

    test('refresh reloads from the start', () async {
      final repo = FakeMessagingRepository()
        ..conversationsToReturn = [testConversation(id: 'conv-1')]
        ..conversationsTotalToReturn = 1;
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, conversationListControllerProvider).close);
      await waitUntil(() => container.read(conversationListControllerProvider).status == ConversationListStatus.success);

      repo.conversationsToReturn = [testConversation(id: 'conv-2', leadName: 'Globex')];
      await container.read(conversationListControllerProvider.notifier).refresh();

      expect(repo.lastConversationsOffset, 0);
      expect(container.read(conversationListControllerProvider).items.map((c) => c.id), ['conv-2']);
    });
  });
}
