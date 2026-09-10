import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/messaging/domain/entities/message_list_state.dart';
import 'package:mobile/features/messaging/presentation/providers/messaging_providers.dart';

import '../../helpers/wait_until.dart';
import 'fake_messaging_repository.dart';
import 'messaging_test_container.dart';

void main() {
  group('MessageListController', () {
    test('loads the conversation history on construction', () async {
      final repo = FakeMessagingRepository()
        ..messagesToReturn = [testMessage(id: 'msg-1')]
        ..messagesTotalToReturn = 1;
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);

      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).status == MessageListStatus.success);

      expect(container.read(messageListControllerProvider('conv-1')).items.map((m) => m.id), ['msg-1']);
    });

    test('an empty history lands in the empty state', () async {
      final repo = FakeMessagingRepository();
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);

      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).status == MessageListStatus.empty);
    });

    test('a load failure lands in the error state with its message', () async {
      final repo = FakeMessagingRepository()..listMessagesError = const NetworkException('Could not reach the server.');
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);

      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).status == MessageListStatus.error);
      expect(container.read(messageListControllerProvider('conv-1')).errorMessage, 'Could not reach the server.');
    });

    test('successfully loading marks the conversation read', () async {
      final repo = FakeMessagingRepository()
        ..messagesToReturn = [testMessage(id: 'msg-1')]
        ..messagesTotalToReturn = 1;
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);

      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).status == MessageListStatus.success);
      await waitUntil(() => repo.markReadCallCount > 0);

      expect(repo.lastMarkReadConversationId, 'conv-1');
    });

    test('loadMore appends the next page', () async {
      final repo = FakeMessagingRepository()
        ..messagesToReturn = [testMessage(id: 'msg-1')]
        ..messagesTotalToReturn = 2;
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);
      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).status == MessageListStatus.success);

      repo.messagesToReturn = [testMessage(id: 'msg-2')];
      await container.read(messageListControllerProvider('conv-1').notifier).loadMore();

      expect(repo.lastMessagesOffset, 1);
      expect(container.read(messageListControllerProvider('conv-1')).items.map((m) => m.id), ['msg-1', 'msg-2']);
    });

    test('sendMessage appends the sent message and returns true', () async {
      final repo = FakeMessagingRepository();
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);
      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).status == MessageListStatus.empty);

      final ok = await container.read(messageListControllerProvider('conv-1').notifier).sendMessage('Hello!');

      expect(ok, isTrue);
      expect(repo.lastSentBody, 'Hello!');
      expect(repo.lastSentConversationId, 'conv-1');
      expect(container.read(messageListControllerProvider('conv-1')).items, hasLength(1));
    });

    test('sendMessage rejects empty/whitespace-only text without calling the repository', () async {
      final repo = FakeMessagingRepository();
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);
      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).status == MessageListStatus.empty);

      final ok = await container.read(messageListControllerProvider('conv-1').notifier).sendMessage('   ');

      expect(ok, isFalse);
      expect(repo.lastSentBody, isNull);
    });

    test('a send failure surfaces the error message and returns false', () async {
      final repo = FakeMessagingRepository()..sendMessageError = const ValidationException('Message is too long.');
      final container = await buildMessagingTestContainer(messagingRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);
      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).status == MessageListStatus.empty);

      final ok = await container.read(messageListControllerProvider('conv-1').notifier).sendMessage('Hello');

      expect(ok, isFalse);
      expect(container.read(messageListControllerProvider('conv-1')).errorMessage, 'Message is too long.');
    });
  });
}
