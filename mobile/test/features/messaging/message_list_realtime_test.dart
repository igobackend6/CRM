import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/messaging/domain/entities/message_list_state.dart';
import 'package:mobile/features/messaging/presentation/providers/messaging_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import 'fake_messaging_repository.dart';
import 'messaging_test_container.dart';

void main() {
  group('MessageListController realtime (Phase 21B)', () {
    test('a new message in this conversation is tail-synced in, not a full reload', () async {
      final repo = FakeMessagingRepository()
        ..messagesToReturn = [testMessage(id: 'm1', body: 'Hi')]
        ..messagesTotalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildMessagingTestContainer(messagingRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);
      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).items.length == 1);

      // The tail-sync fetch (offset = items already loaded) returns just
      // the new message — not the whole history.
      repo
        ..messagesToReturn = [testMessage(id: 'm2', body: 'From the other side')]
        ..messagesTotalToReturn = 2;
      realtime.emitInsert('messages', {'id': 'm2', 'workspace_id': 'w1', 'conversation_id': 'conv-1'});

      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).items.length == 2);
      final state = container.read(messageListControllerProvider('conv-1'));
      expect(state.items.last.id, 'm2');
      expect(repo.lastMessagesOffset, 1); // fetched starting right after what was already loaded
    });

    test('the optimistic local echo is not duplicated when the realtime insert for it arrives', () async {
      final repo = FakeMessagingRepository()
        ..messagesToReturn = []
        ..messagesTotalToReturn = 0
        ..sendMessageResult = testMessage(id: 'm1', body: 'Hello');
      final realtime = FakeRealtimeService();
      final container = await buildMessagingTestContainer(messagingRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);
      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).status == MessageListStatus.empty);

      await container.read(messageListControllerProvider('conv-1').notifier).sendMessage('Hello');
      expect(container.read(messageListControllerProvider('conv-1')).items, hasLength(1));

      // The realtime echo of the very message just sent shouldn't
      // re-fetch a duplicate — the tail-sync dedupes by id.
      repo
        ..messagesToReturn = [testMessage(id: 'm1', body: 'Hello')]
        ..messagesTotalToReturn = 1;
      realtime.emitInsert('messages', {'id': 'm1', 'workspace_id': 'w1', 'conversation_id': 'conv-1'});

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(container.read(messageListControllerProvider('conv-1')).items, hasLength(1));
    });

    test('a read-state update on an already-loaded message patches it in place', () async {
      final repo = FakeMessagingRepository()
        ..messagesToReturn = [testMessage(id: 'm1', body: 'Hi')]
        ..messagesTotalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildMessagingTestContainer(messagingRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);
      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).items.length == 1);
      expect(container.read(messageListControllerProvider('conv-1')).items.single.readAt, isNull);

      realtime.emitUpdate('messages', {
        'id': 'm1',
        'workspace_id': 'w1',
        'conversation_id': 'conv-1',
        'read_at': '2026-01-01T09:05:00+00:00',
      });

      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).items.single.readAt != null);
    });

    test('an event for a different conversation is ignored', () async {
      final repo = FakeMessagingRepository()
        ..messagesToReturn = [testMessage(id: 'm1', body: 'Hi')]
        ..messagesTotalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildMessagingTestContainer(messagingRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageListControllerProvider('conv-1')).close);
      await waitUntil(() => container.read(messageListControllerProvider('conv-1')).items.length == 1);

      repo.messagesToReturn = [testMessage(id: 'm1'), testMessage(id: 'm2', conversationId: 'conv-2')];
      realtime.emitInsert('messages', {'id': 'm9', 'workspace_id': 'w1', 'conversation_id': 'conv-2'});

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(container.read(messageListControllerProvider('conv-1')).items, hasLength(1));
    });
  });
}
