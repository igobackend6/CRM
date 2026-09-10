import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/messaging/presentation/providers/messaging_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import 'fake_messaging_repository.dart';
import 'messaging_test_container.dart';

void main() {
  group('ConversationListController realtime (Phase 21B)', () {
    test('a new message elsewhere debounces a refresh of the conversation list', () async {
      final repo = FakeMessagingRepository()
        ..conversationsToReturn = [testConversation(id: 'c1')]
        ..conversationsTotalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildMessagingTestContainer(messagingRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, conversationListControllerProvider).close);
      await waitUntil(() => container.read(conversationListControllerProvider).items.length == 1);

      repo
        ..conversationsToReturn = [testConversation(id: 'c1', latestMessagePreview: 'New message', unreadCount: 1)]
        ..conversationsTotalToReturn = 1;
      realtime.emitInsert('messages', {'id': 'm2', 'workspace_id': 'w1', 'conversation_id': 'c1'});

      await waitUntil(() => container.read(conversationListControllerProvider).items.first.latestMessagePreview == 'New message');
    });

    test('an event on an unrelated table is ignored', () async {
      final repo = FakeMessagingRepository()
        ..conversationsToReturn = [testConversation(id: 'c1')]
        ..conversationsTotalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildMessagingTestContainer(messagingRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, conversationListControllerProvider).close);
      await waitUntil(() => container.read(conversationListControllerProvider).items.length == 1);

      repo.conversationsToReturn = [testConversation(id: 'c1'), testConversation(id: 'c2')];
      realtime.emitInsert('leads', {'id': 'l1', 'workspace_id': 'w1'});

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(container.read(conversationListControllerProvider).items, hasLength(1));
    });
  });
}
